# ADR 0017: trino-init retries queries, not just the readiness probe

Status: Accepted
Date: 2026-08-12

## Context
While bringing up the Apicurio Registry service (ADR 0016), `trino-init`
failed on a fresh `docker compose up --build` with `Query ... failed:
Trino server is still initializing`, even though `trino`'s own healthcheck
(`curl -f http://localhost:8080/v1/info`) had already reported healthy and
`trino-init depends_on trino: condition: service_healthy` had let the
container start.

This is not an ordering bug of the kind fixed in ADR 0011/0013/0014 (a
service starting before something it needs exists). It's a narrower gap:
Trino's `/v1/info` endpoint can return HTTP 200 while the coordinator is
still internally in `SERVER_STARTING_UP` and hasn't finished discovering
its own worker node yet. A query issued in that window fails with "No
nodes available to run query" (or, as seen here, "Trino server is still
initializing") — confirmed as a known, previously-reported Trino behavior
(testcontainers-java issue #6310), not something specific to this stack or
this Docker Compose setup. `/v1/info` answers "is the HTTP server up",
not "is the query engine ready to run queries" — two different questions
that happen to usually resolve close together, except when they don't.

## Decision
`trino-init` now retries the actual `CREATE SCHEMA` statement (up to 12
attempts, 5s apart — 60s of headroom, well beyond the few seconds this gap
typically lasts) instead of assuming one attempt is enough once the
healthcheck has passed. This closes the actual gap that caused the
failure, rather than the one ADR 0011/0013/0014 already closed (which was
services starting before their dependencies were healthy at all — this is
a different failure mode from the same service passing its healthcheck too
early).

**Moved the retry logic into a mounted script
(`trino-init/init-schemas.sh`) instead of inlining it in the
`docker-compose.yml` entrypoint string.** The retry loop needs a shell
variable and a `while`, and getting that correct inline means fighting
three stacked layers of escaping simultaneously: YAML's own scalar rules,
Docker Compose's `$`/`$$` variable-interpolation pass (which runs over
every string in the file before it ever reaches a shell), and POSIX shell
quoting. A first attempt at inlining this produced a subtle-but-real
correctness bug — a `for`/`sleep` loop whose exit status didn't correctly
propagate failure on the truly-never-ready case, silently reported success
regardless — caught by tracing through the escaping layers by hand before
running it, rather than discovering it live. Using `entrypoint: ["/bin/sh",
"/init-schemas.sh"]` (list form) sidesteps Compose's shell-string handling
entirely: it's an exact argv, and the actual retry logic lives in ordinary,
readable shell where variables and loops don't need any of that.

## Consequences
- `run_with_retry` in the script returns non-zero (and the script exits
  non-zero, correctly failing the `trino-init` container) if Trino is
  genuinely broken and never becomes queryable within 60s — it doesn't
  paper over a real failure, only the specific narrow timing gap this ADR
  targets.
- This pattern (mounted script instead of inline entrypoint string) is
  worth reaching for by default going forward whenever init logic needs
  more than a straight-line sequence of commands — the escaping-layer risk
  doesn't go away just because a given inline attempt happens to work.
