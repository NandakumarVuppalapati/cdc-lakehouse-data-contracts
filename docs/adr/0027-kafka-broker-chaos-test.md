# ADR 0027: Kafka broker chaos test — real outage, measured recovery

Status: Accepted (design verified against Kafka Connect's real REST API
docs and this project's own prior ADR 0021 findings; **not yet run** —
see Consequences)
Date: 2026-08-20

## Context
Tier 2's last item: prove the pipeline actually recovers from a real
infrastructure failure, with a measured recovery time — not just that it
works when nothing goes wrong. This project's own history already has a
directly relevant data point: ADR 0021 found that a *different* kind of
Kafka Connect failure (a source task permanently stuck replaying a
poisoned WAL entry) does **not** self-heal via a plain restart — the same
failure recurs on every retry, because retrying doesn't change the
underlying cause. A broker outage is a structurally different failure
(transient — connectivity, not data), but that prior finding is a good
reason not to *assume* Kafka Connect self-heals cleanly here either
without actually checking.

## Decision
`chaos/kafka_broker_chaos_test.py` — stdlib-only Python (same "no new
dependency for a cross-cutting script" pattern as
`dbt/run_with_metrics.py`, ADR 0024), runnable directly by the user
(`python chaos/kafka_broker_chaos_test.py`) against their own live stack.

**Failure injected**: `docker kill lakehouse-kafka` — an ungraceful kill
(not `docker stop`), on the single broker in this project's single-node
KRaft cluster. Since there's exactly one broker, this is a full outage of
the entire message bus, not a partial-cluster failure — the most severe
version of "Kafka goes away" this stack can experience.

**Marker rows, not a row-count diff**: before killing the broker, insert
a handful of `shop.customers` rows with a timestamped, greppable email
prefix (`chaos-test-<epoch>-N@example.com`). This makes the final data-
integrity check a precise "did these exact N rows arrive" query instead
of an approximate before/after row count that could be confounded by
whatever else is happening in the stack.

**Recovery detection, not recovery assumption**: the script polls Kafka
Connect's `GET /connectors?expand=status` every 3s throughout the outage,
logging every connector/task state transition it actually observes — it
does not assume tasks will flip to `FAILED` (they might just retry
silently against the broker and never leave `RUNNING` at the framework-
state level, since a "state" in Connect's status API reflects the
framework's view, not necessarily every retry happening underneath it).
Whichever behavior actually occurs gets logged and printed, honestly.

**Recovery action, not recovery hope**: once the broker's own healthcheck
reports healthy again, the script calls
`POST /connectors/{name}/restart?includeTasks=true&onlyFailed=true` on
all five connectors (the source + four sinks, real names confirmed
against `scripts/register-connectors.sh` and `kafka-connect/connectors/`,
not guessed). This is KIP-745's documented restart API (Kafka Connect
3.0+) — confirmed against Apache Kafka's own REST API reference before
using it, same discipline as every other REST call this project has
added (ADR 0021's Offsets API usage, ADR 0016/0013's healthcheck
endpoints). `onlyFailed=true` makes this call a safe no-op for any
connector/task that already self-healed on its own — the script doesn't
need to know in advance which behavior actually occurred to do the right
thing.

**Data-loss check handed to the user, not automated**: the script prints
a copy-pasteable Trino query
(`SELECT after.email, after.full_name FROM iceberg.bronze.customers
WHERE after.email LIKE 'chaos-test-<marker>-%'`) rather than querying
Trino itself. Trino's client protocol (`POST /v1/statement`, then follow
`nextUri` until the query leaves `QUEUED`/`RUNNING`) is a real,
implementable thing, but this project has a specific, documented history
(ADR 0006 through 0008) of what happens when it assumes the internals of
a tool it hasn't actually exercised — a hand-verified query the user runs
themselves in the Trino UI is the honest choice over an unverified,
untested Trino HTTP client written by a session with no way to run it
against a real Trino instance.

**Expected result, stated honestly in the script's own output**: *more*
than 3 marker rows landing is expected and correct, not a bug — Debezium/
Kafka Connect's documented delivery guarantee is at-least-once, not
exactly-once, and Silver's existing dedup-by-latest-`ts_ms` logic
(already built, ADR-documented in the Silver models) already absorbs
duplicate envelopes for any table that reaches Silver. *Fewer* than 3 is
the actual failure signal — real data loss.

## Alternatives considered
- **Corrupting a message instead of killing the broker**: closer to
  "bad data," but that failure mode is already covered by the Apicurio
  (layer 1) and Great Expectations (layer 3) demos — this ADR's job is to
  cover a category this project hadn't demonstrated yet: infrastructure
  failure and recovery, not data-quality failure.
- **Killing `kafka-connect` instead of `kafka`**: rejected — Kafka
  Connect restarting is a much less interesting/severe failure (it's
  explicitly designed to be restarted; a fresh container just reloads
  connector configs from Kafka's internal topics, as ADR 0021 already
  observed happening incidentally after a Docker Desktop restart). The
  broker itself going away is the harder, more representative failure for
  a pipeline whose entire job is streaming through Kafka.
- **A fixed sleep instead of polling for the FAILED state / healthcheck**:
  rejected — this project's own `trino-init/init-schemas.sh` already
  established the "retry against a real signal, don't trust a fixed
  sleep" pattern (ADR 0017); a chaos test measuring *recovery time* would
  be self-defeating if it used a guessed sleep instead of a real signal
  for its own timing.

## Consequences
- **Not yet run.** No live Docker daemon access this session (the
  standing constraint behind every "not yet run" ADR in this series).
  The script compiles clean (`python3 -m py_compile`, checked) and every
  REST call/endpoint it makes is one this project has either already used
  successfully (`?expand=status`, health checks) or freshly confirmed
  against Kafka's own documentation (the KIP-745 restart endpoint) — but
  the actual behavior of a live single-broker Kafka cluster under a real
  `docker kill`, and how long Debezium/the Iceberg sink connectors
  actually take to recover, is unobserved until the user runs this for
  real.
- `14-chaos-test-recovery.png` stays `[ ]` in `PORTFOLIO_ASSETS.md` until
  a real run produces recovery-time numbers worth capturing — ideally the
  full terminal output (marker insert -> kill -> observed failure ->
  restart -> recovery timing -> the Trino row-count confirmation), since
  that tells the whole story in one screenshot.
- If the observed behavior turns out to need something this script
  doesn't yet handle (e.g. the source connector's replication slot itself
  needing attention after an outage — a plausible echo of ADR 0021's
  slot-related findings, though for a structurally different reason),
  that's a real follow-up to write up as its own ADR once observed, not
  something to guess at and patch in now.
