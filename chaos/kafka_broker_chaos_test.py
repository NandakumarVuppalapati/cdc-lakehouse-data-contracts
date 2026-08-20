#!/usr/bin/env python3
"""
Chaos test: kill the single Kafka broker mid-flight, confirm Debezium's
source connector and the four Iceberg sink connectors actually recover,
and measure how long that takes. Stdlib-only Python (urllib, subprocess,
json) so it runs the same way on the user's own machine as
dbt/run_with_metrics.py already does — no extra install step. See
docs/adr/0027 for the full design writeup and why "recovery" here means
"detect FAILED, then trigger Kafka Connect's own documented restart API"
rather than assuming everything self-heals with zero intervention (this
project's own ADR 0021 already found, for a different failure mode, that
plain retries don't always cut it).

Usage (from the repo root, with the full stack already up via
`docker compose up -d` and connectors registered via
`scripts/register-connectors.sh`):

    python chaos/kafka_broker_chaos_test.py

What it does, in order:
  1. Confirms the stack is actually healthy before breaking anything —
     refuses to run a chaos test against a stack that's already broken.
  2. Inserts a handful of distinctively-marked rows into
     shop.customers, so there's a real, checkable payload in flight.
  3. `docker kill`s the kafka container — a full, ungraceful outage of the
     only broker in this single-node cluster, not a graceful stop.
  4. Polls Kafka Connect's connector/task status every 3s, logging every
     state transition, until either everything is FAILED (or the poll
     window elapses) — this is the "how does Kafka Connect actually
     behave when its broker vanishes" observation, not assumed.
  5. `docker start`s the kafka container back up, waits for its own
     healthcheck to report healthy.
  6. Calls the documented Kafka Connect REST API restart-if-failed
     endpoint (KIP-745, `POST .../restart?includeTasks=true&onlyFailed=true`)
     on every connector — a safe no-op for any connector that self-healed
     on its own, and the actual fix for any that didn't.
  7. Polls until every connector/task is back to RUNNING/RUNNING, prints
     total recovery time.
  8. Prints the exact Trino query to confirm the marker rows actually made
     it all the way to iceberg.bronze.customers — this script does not
     drive Trino itself (its client protocol is multi-step and this
     project's own history — ADR 0006 through 0008 — is a record of what
     happens when this codebase guesses at what's inside someone else's
     tool instead of checking; a copy-pasteable query the user runs
     directly is the honest choice here over an unverified Trino client
     implementation).
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

CONNECT_URL = "http://localhost:8083"
KAFKA_CONTAINER = "lakehouse-kafka"
POSTGRES_CONTAINER = "lakehouse-postgres"
CONNECTOR_NAMES = [
    "shop-postgres-source",
    "iceberg-sink-customers",
    "iceberg-sink-products",
    "iceberg-sink-orders",
    "iceberg-sink-order-items",
]
POLL_INTERVAL_SECONDS = 3
FAILURE_DETECT_TIMEOUT_SECONDS = 120
RECOVERY_TIMEOUT_SECONDS = 300


def http_get_json(url: str):
    with urllib.request.urlopen(url, timeout=10) as resp:
        return json.load(resp)


def http_post(url: str) -> int:
    req = urllib.request.Request(url, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as exc:
        return exc.code


def connector_states():
    """Returns {connector_name: {"connector": state, "tasks": [state, ...]}}."""
    data = http_get_json(f"{CONNECT_URL}/connectors?expand=status")
    out = {}
    for name, info in data.items():
        status = info["status"]
        out[name] = {
            "connector": status["connector"]["state"],
            "tasks": [t["state"] for t in status["tasks"]],
        }
    return out


def print_states(states, label: str) -> None:
    print(f"\n[{label}]")
    for name, s in states.items():
        print(f"  {name}: connector={s['connector']} tasks={s['tasks']}")


def all_healthy(states) -> bool:
    for s in states.values():
        if s["connector"] != "RUNNING":
            return False
        if any(t != "RUNNING" for t in s["tasks"]):
            return False
    return True


def any_failed(states) -> bool:
    for s in states.values():
        if s["connector"] == "FAILED":
            return True
        if any(t == "FAILED" for t in s["tasks"]):
            return True
    return False


def docker(*args) -> None:
    subprocess.run(["docker", *args], check=True)


def insert_marker_rows(marker: str, count: int = 3) -> None:
    values = ", ".join(
        f"('chaos-test-{marker}-{i}@example.com', 'Chaos Test {marker}-{i}', 'ZZ')"
        for i in range(count)
    )
    sql = (
        "INSERT INTO shop.customers (email, full_name, country) VALUES "
        f"{values};"
    )
    print(f"\nInserting {count} marker rows (email prefix chaos-test-{marker}-) ...")
    subprocess.run(
        ["docker", "exec", "-i", POSTGRES_CONTAINER, "psql", "-U", "lakehouse", "-d", "sourcedb", "-c", sql],
        check=True,
    )


def wait_for(predicate, timeout: int, poll_label: str):
    start = time.time()
    last_states = None
    while time.time() - start < timeout:
        try:
            states = connector_states()
        except (urllib.error.URLError, OSError) as exc:
            print(f"  ({poll_label}) Connect REST API unreachable yet: {exc}")
            time.sleep(POLL_INTERVAL_SECONDS)
            continue
        if states != last_states:
            print_states(states, poll_label)
            last_states = states
        if predicate(states):
            return states, time.time() - start
        time.sleep(POLL_INTERVAL_SECONDS)
    return last_states, time.time() - start


def main() -> None:
    marker = str(int(time.time()))

    print("=== Step 1: pre-flight check ===")
    try:
        pre_states = connector_states()
    except (urllib.error.URLError, OSError) as exc:
        print(f"Kafka Connect not reachable at {CONNECT_URL}: {exc}")
        print("Bring the stack up and register connectors first — see scripts/register-connectors.sh.")
        sys.exit(1)
    print_states(pre_states, "before chaos")
    if not all_healthy(pre_states):
        print("\nStack is not fully healthy already — refusing to run a chaos test")
        print("against a stack that's already broken. Fix that first.")
        sys.exit(1)

    print("\n=== Step 2: insert marker rows ===")
    insert_marker_rows(marker)

    print(f"\n=== Step 3: docker kill {KAFKA_CONTAINER} ===")
    kill_time = time.time()
    docker("kill", KAFKA_CONTAINER)
    print(f"Killed at {time.strftime('%H:%M:%S', time.localtime(kill_time))}")

    print("\n=== Step 4: observe failure (polling Kafka Connect) ===")
    failure_states, detect_elapsed = wait_for(
        any_failed, FAILURE_DETECT_TIMEOUT_SECONDS, "during outage"
    )
    if failure_states and any_failed(failure_states):
        print(f"\nObserved a FAILED connector/task after {detect_elapsed:.1f}s.")
    else:
        print(
            f"\nNo FAILED state observed within {FAILURE_DETECT_TIMEOUT_SECONDS}s — "
            "tasks may be silently retrying against the broker without ever "
            "flipping to FAILED. Proceeding to bring the broker back regardless."
        )

    print(f"\n=== Step 5: docker start {KAFKA_CONTAINER}, wait for healthy ===")
    restart_time = time.time()
    docker("start", KAFKA_CONTAINER)
    broker_healthy_at = None
    while time.time() - restart_time < 120:
        result = subprocess.run(
            ["docker", "inspect", "--format={{.State.Health.Status}}", KAFKA_CONTAINER],
            capture_output=True, text=True, check=True,
        )
        status = result.stdout.strip()
        print(f"  kafka health: {status}")
        if status == "healthy":
            broker_healthy_at = time.time()
            break
        time.sleep(POLL_INTERVAL_SECONDS)
    if broker_healthy_at is None:
        print("Broker did not report healthy within 120s — check `docker logs lakehouse-kafka`.")
        sys.exit(1)
    print(f"Broker healthy again after {broker_healthy_at - restart_time:.1f}s.")

    print("\n=== Step 6: trigger Kafka Connect's documented restart-if-failed API ===")
    # KIP-745 (Kafka Connect 3.0+), confirmed against Apache Kafka's own
    # REST API docs before using this — see docs/adr/0027. Safe no-op for
    # any connector that already self-healed.
    for name in CONNECTOR_NAMES:
        status = http_post(f"{CONNECT_URL}/connectors/{name}/restart?includeTasks=true&onlyFailed=true")
        print(f"  POST .../{name}/restart?includeTasks=true&onlyFailed=true -> {status}")

    print("\n=== Step 7: wait for full recovery ===")
    recovery_states, recovery_elapsed = wait_for(
        all_healthy, RECOVERY_TIMEOUT_SECONDS, "recovering"
    )
    total_elapsed = time.time() - kill_time

    print("\n=== Result ===")
    if recovery_states and all_healthy(recovery_states):
        print(f"All connectors/tasks RUNNING again.")
        print(f"Broker down -> broker healthy:        {broker_healthy_at - kill_time:.1f}s")
        print(f"Broker healthy -> connectors RUNNING:  {recovery_elapsed:.1f}s")
        print(f"Total (kill -> fully recovered):       {total_elapsed:.1f}s")
    else:
        print(f"NOT fully recovered within {RECOVERY_TIMEOUT_SECONDS}s — investigate manually:")
        print(f"  curl -s {CONNECT_URL}/connectors?expand=status | python3 -m json.tool")

    print("\n=== Step 8: confirm no data loss ===")
    print("Run this in the Trino UI (http://localhost:8082) or CLI to confirm")
    print(f"all {3} marker rows made it all the way to Iceberg, post-recovery:")
    print(
        f"\n  SELECT after.email, after.full_name\n"
        f"  FROM iceberg.bronze.customers\n"
        f"  WHERE after.email LIKE 'chaos-test-{marker}-%';\n"
    )
    print("Expect 3 rows. Fewer means the outage caused real data loss —")
    print("more than 3 (duplicates) is expected and fine: at-least-once")
    print("delivery is Debezium/Kafka Connect's documented guarantee, not")
    print("exactly-once, and Silver's dedup-by-latest-ts_ms logic already")
    print("handles duplicate envelopes for any table that reaches Silver.")


if __name__ == "__main__":
    main()
