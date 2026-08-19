#!/usr/bin/env python3
"""
Wraps the real `dbt` binary: times the invocation, then pushes build
duration / success / test-failure-count to Prometheus Pushgateway so
Grafana has something to show for every `docker compose run --rm dbt ...`
(see observability/ and ADR 0024). Standard-library only (urllib, json,
subprocess) — the dbt image is deliberately minimal (python:3.11-slim +
dbt-trino only, see ADR 0015), and this is a single cross-cutting concern,
not worth a new dependency.

Transparent to every existing usage: argv passes straight through to the
real `dbt` command, and this script's own exit code is dbt's exit code.
`docker compose run --rm dbt build` / `... test` / `... run` / the
compose-file default `--version` all behave exactly as before; the only
difference is a metrics push happens afterward.
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

PUSHGATEWAY_URL = "http://pushgateway:9091/metrics/job/dbt_build"
RUN_RESULTS_PATH = "target/run_results.json"


def count_test_failures() -> int:
    # dbt's run_results.json is a documented, stable dbt-core artifact
    # (https://docs.getdbt.com/reference/artifacts/run-results-json):
    # a `results` list, each entry with `unique_id` and `status`
    # ("pass"/"fail"/"error"/"skipped"/"warn"). Only unique_ids starting
    # with "test." are counted — a failed *model* (e.g. a Model Contract
    # violation) already fails this whole invocation and shows up in
    # dbt_build_success, so counting it here too would double-count the
    # same failure under two different panels.
    try:
        with open(RUN_RESULTS_PATH) as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return 0
    return sum(
        1
        for result in data.get("results", [])
        if result.get("unique_id", "").startswith("test.")
        and result.get("status") not in ("pass", "skipped")
    )


def push_metrics(duration_seconds: float, success: bool, test_failures: int) -> None:
    body = (
        "# TYPE dbt_build_duration_seconds gauge\n"
        f"dbt_build_duration_seconds {duration_seconds}\n"
        "# TYPE dbt_build_success gauge\n"
        f"dbt_build_success {1 if success else 0}\n"
        "# TYPE dbt_test_failures gauge\n"
        f"dbt_test_failures {test_failures}\n"
    ).encode()
    try:
        req = urllib.request.Request(PUSHGATEWAY_URL, data=body, method="PUT")
        urllib.request.urlopen(req, timeout=10)
    except (urllib.error.URLError, OSError) as exc:
        # An observability hiccup must never mask, or change the exit code
        # of, the real dbt result — log to stderr and move on.
        print(f"[run_with_metrics] warning: failed to push to Pushgateway: {exc}", file=sys.stderr)


def main() -> None:
    args = sys.argv[1:]
    start = time.time()
    proc = subprocess.run(["dbt"] + args)
    duration = time.time() - start
    success = proc.returncode == 0
    push_metrics(duration, success, count_test_failures())
    sys.exit(proc.returncode)


if __name__ == "__main__":
    main()
