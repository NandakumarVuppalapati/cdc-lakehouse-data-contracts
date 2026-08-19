# ADR 0023: GitHub Actions CI — full real pipeline, not seeded Bronze

Status: Accepted (design verified against docs/existing scripts; **not yet
verified against a live GitHub Actions run** — see Consequences)
Date: 2026-08-18

## Context
This project's whole thesis is that bad changes get caught at multiple
independent layers before they reach a dashboard. Every layer so far
(Apicurio/ADR 0016+0019, dbt Model Contracts/ADR 0011, Great Expectations/
ADR 0020) has been demoed and captured manually, on one machine, by one
person. A CI workflow that reruns the same demo automatically, on every
push, is the only version of "proof" that doesn't depend on trusting a
screenshot — it's the single most important portfolio asset for that
reason (see PORTFOLIO_ASSETS.md item 10).

Three ways to scope it were on the table: (a) seed Bronze directly with SQL
and skip Kafka/Debezium/Apicurio entirely, (b) a hybrid (real CDC for the
happy path, seeded data for the breaking-change assertion), (c) the full
real pipeline for everything, start to finish. Asked directly, the answer
was (c) — full pipeline, no shortcuts, even though it's the slowest and
most failure-prone of the three to get running in CI. The value of this
project's portfolio asset is specifically "the pipeline catches a bad
change end to end," and that claim is weaker if the CI proof doesn't
actually exercise Debezium/Kafka/Apicurio.

GitHub-hosted public runners (confirmed via WebSearch, 2026): 4 vCPU / 16GB
RAM / 14GB disk. This stack runs five JVM processes simultaneously (Kafka,
Kafka Connect, Trino, Nessie, Apicurio) plus Postgres and MinIO — a real
memory-pressure risk that local dev doesn't necessarily surface the same
way, depending on how much RAM Docker Desktop was given locally.

## Decision
`.github/workflows/ci.yml`, one job, full docker-compose stack:

1. `docker compose up -d --wait` on the infra tier only (`postgres kafka
   kafka-connect minio minio-init nessie trino trino-init apicurio`) —
   deliberately excludes `dagster` (not needed to prove the pipeline/
   contracts, and it's another JVM+Python container) and lets `dbt`'s
   default one-shot sit out too; both are invoked explicitly via
   `docker compose run --rm` where actually needed. `--wait` replaces a
   hand-rolled sleep loop with Compose's own healthcheck-aware blocking.
2. `scripts/register-connectors.sh` (reused as-is — no CI-specific
   version) to register the real Debezium + Iceberg sink connectors.
3. An explicit task-status check beyond the register script's own exit
   code. This is a direct lesson from ADR 0021: a connector can register
   successfully while its task is silently FAILED underneath it (that's
   exactly what happened with the stuck WAL replay). The register script
   wasn't designed to catch that case, so CI checks
   `/connectors?expand=status` itself and fails the job if any task isn't
   `RUNNING`, rather than trusting "registered" to mean "working."
4. Poll `bronze.orders` via `docker exec lakehouse-trino trino ...` until
   the seed rows appear (proves the full CDC path, not just that Postgres
   has data) — using the real Bronze schema shape (`before`/`after`/`op`/
   `ts_ms`, per `sources.yml` and `silver_orders.sql`), not a guessed one.
5. Happy path: `docker compose run --rm dbt build` then `... great-
   expectations`, both expected to exit 0.
6. Breaking change: `UPDATE shop.orders SET status = 'shpped' WHERE
   order_id = 2` directly against Postgres via `docker exec` — the same
   demo already proven manually and captured as
   `docs/assets/08-great-expectations-failure.jpg`. Chosen over the dbt
   Model Contract demo (renaming `customer_name`, ADR 0012) because it
   needs no file mutation (no risk of a `sed`/revert step leaving the repo
   dirty or racing a real edit), and it's the layer this project's
   Tier 1 work spent the most effort building out (ADR 0020/0021).
7. Poll Bronze again for the bad value to actually land via CDC (not just
   assume 10s is enough — same retry-loop pattern as step 4).
8. `dbt build` again — expected to **pass**. This is the point: a Model
   Contract is shape-only, and `'shpped'` is exactly as valid a varchar as
   `'shipped'`. If this step fails, something else broke.
9. Great Expectations again — expected to **fail**. The exit-code check is
   deliberately inverted: the step captures GX's exit code, and turns a
   GX *pass* (exit 0) into a workflow **failure** with an explicit
   `::error::`. This was the one design point worth being paranoid about —
   it would be easy to write this step so that CI stays green regardless
   of whether GX actually caught anything, which would make the whole
   asset dishonest. The current form fails loudly in exactly the case
   that matters: contract layer 3 silently not catching a regression it
   exists to catch.
10. `$GITHUB_STEP_SUMMARY` written with a short markdown recap (this is
    also what the asset-10 screenshot should end up capturing).
11. `docker compose logs` uploaded as an artifact on failure, `docker
    compose down -v` always runs — ephemeral runner, but leaves a clean
    debugging trail rather than depending on GitHub's own container
    lifecycle cleanup.

## Alternatives considered
- **Seed Bronze directly (option a)**: fastest, least flaky, but proves
  nothing about Debezium/Kafka/Apicurio actually working — explicitly
  rejected.
- **Hybrid (option b)**: real CDC for setup, seeded data for the breaking
  change. Rejected for the same reason as (a) once (c) was chosen: the
  breaking-change assertion is the part that actually needs to be
  trustworthy, so shortcutting it defeats the point.
- **Two jobs (GX-layer break + dbt-Model-Contract break)**: considered,
  since ADR 0012's `customer_name` -> `cust_name` rename is an equally
  real, already-proven demo of a *different* contract layer. Not included
  in this workflow — it would mean a second full stack bring-up (roughly
  doubling CI time and JVM memory pressure for the same runner) and it
  requires mutating a tracked model file mid-job (sed + assert + revert),
  which is a meaningfully different failure-mode shape than the SQL-only
  GX demo. Left as a documented follow-up rather than guessed into this
  workflow under time pressure.
- **JVM heap tuning for CI** (smaller `-Xmx` for Kafka/Trino/Nessie/
  Apicurio to fit the 16GB runner more comfortably): considered but not
  applied. None of these services have explicit heap flags in
  `docker-compose.yml` today, and adding untested flags to the file real
  local dev depends on — based on a runner-memory concern that hasn't
  actually been observed failing — risked fixing a hypothetical problem by
  introducing a real one. Flagged here as the first thing to look at if a
  real run OOMs.

## Consequences
- **This has not been run against real GitHub Actions.** `git remote -v`
  on this repo returns nothing — there's no GitHub remote configured yet,
  so nothing has triggered this workflow. Everything in it is built
  against the project's own already-proven local commands
  (`register-connectors.sh`, the retry-loop pattern from
  `trino-init/init-schemas.sh`, the exact Bronze schema shape used in
  `silver_orders.sql`) and documented tool behavior (Compose `--wait`,
  GitHub-hosted runner specs), not assumption — but "verified against
  primary sources" is not the same guarantee as "verified by actually
  running it," which is this project's normal bar (every other ADR here
  reflects a real run, including real failures). The honest status is:
  designed carefully, not yet exercised. First real run should be treated
  as a debugging session, not a formality — most likely failure points are
  Kafka Connect readiness timing (no healthcheck defined on that service
  today) and runner memory pressure under five simultaneous JVMs.
- Once pushed and green, `10-ci-breaking-change-test.png` (or a GIF of the
  Summary tab) becomes capturable — still marked `[ ]` in
  PORTFOLIO_ASSETS.md until that real run exists.
- CI runtime is expected to be several minutes slower than a
  seeded-data-only approach would have been (image builds + full stack
  health-wait + two full dbt+GX cycles + two CDC-propagation polls) — an
  accepted, explicit trade for the fidelity of the "full pipeline" scope
  chosen.
