# ADR 0026: Terraform (kreuzwerker/docker provider) for local IaC

Status: Accepted (every resource attribute checked against the provider's
real docs; HCL syntax verified with a parser; **not yet applied against a
live Docker daemon** — see Consequences)
Date: 2026-08-20

## Context
`infra/terraform/README.md` has scoped this since early in the project:
`local/` should provision the exact same compose stack declaratively
(`terraform apply` instead of `docker compose up`), demonstrating real IaC
literacy rather than just writing Dockerfiles and a compose file. This
session's tooling has no Docker daemon access at all (confirmed
repeatedly across this project — no Docker Desktop reachable from the
sandbox that writes this code), so unlike every other Tier 1/2 piece,
this one cannot be smoke-tested by running it even once before handing it
to the user.

## Decision
`kreuzwerker/docker` provider, version `4.5.0` — confirmed as the current
published version on the Terraform Registry before pinning (not the
`docker/docker` namespace, which is a different, less commonly used
provider for this use case).

`infra/terraform/local/` mirrors `docker-compose.yml` file-for-file:
`network.tf` (the network + all six named volumes, plus a seventh for
Marquez's dedicated Postgres), then one `.tf` file per logical service
group (`postgres.tf`, `kafka.tf`, `kafka_connect.tf`, `minio.tf`,
`nessie.tf`, `trino.tf`, `apicurio.tf`, `dbt.tf`,
`great_expectations.tf`, `dagster.tf`, `observability.tf`, `marquez.tf`).
Same container names, same network name, same host ports as the compose
file — this is meant to be a genuine alternative provisioner for the
*identical* infrastructure, not a parallel toy stack with different
names. Consequence: don't run `docker compose up` and `terraform apply`
at the same time (`docker compose down` first) — both would try to
create resources with the same names and collide.

**Every resource schema (`docker_network`, `docker_volume`,
`docker_image`, `docker_container`, including the `build`, `healthcheck`,
`mounts`, `networks_advanced`, and `ports` nested blocks) was checked
against the provider's actual current documentation
(`github.com/kreuzwerker/terraform-provider-docker/docs`) before writing
any HCL — not written from memory/assumption about what a Docker
Terraform provider "probably" looks like.** This matters specifically
because this provider's schema has real, non-obvious details: the
`healthcheck` block's `test` field takes the same list-of-strings form as
a Dockerfile `HEALTHCHECK`, `wait`/`wait_timeout` on `docker_container` is
what makes Terraform actually block until a container reports healthy
(the equivalent of Compose's `condition: service_healthy`), and `attach`
+ `must_run = false` is the equivalent for one-shot jobs
(`condition: service_completed_successfully`) — `attach` waits for the
container's execution to finish rather than just for it to start.

**Two scope decisions, both mirroring existing compose behavior rather
than inventing new behavior:**
- `dbt` and `dagster`/`great-expectations` real invocations
  (`dbt build`, a "Materialize all" run) are ad hoc actions a person
  takes against a running stack, not infrastructure-provisioning steps —
  Terraform's job here stops at bringing the same containers up that
  `docker compose up -d` would, exactly like the compose file's own `dbt`
  service only running a `--version` smoke test by default.
- `great-expectations` is gated behind `var.run_gx_job` (default `false`)
  — Terraform has no native equivalent of Compose's `profiles`, so a
  `count`-gated resource is the closest honest mirror of that service's
  `profiles: ["jobs"]` exclusion from a plain `up -d`.

**Windows path handling — a known, unverified risk, not swept under the
rug.** Several containers here bind-mount host files/directories
(`postgres/init.sql`, `trino/catalog/`, `dbt/cdc_lakehouse/`, ...).
Terraform's own `abspath()` can return backslash-separated paths on
native Windows, and this provider talks to the Docker daemon's HTTP API
directly (not through the `docker` CLI's own path-translation layer), so
whether Docker Desktop's WSL2 backend correctly resolves a raw Windows
path passed this way has not been confirmed. `variables.tf` defensively
forward-slashes every path it builds (`replace(..., "\\", "/")`) as a
best-effort mitigation, but this is exactly the kind of thing this
project's own discipline says shouldn't be asserted as "working" without
having watched it work. If `terraform apply` fails on a bind-mount path
error, running it from inside WSL2 (pointing at the repo via its
`/mnt/c/...` path) is the documented fallback.

## A real bug this exercise caught
Re-deriving every port mapping from `docker-compose.yml` while writing
this surfaced the same `pushgateway`/`apicurio` host-port-9091 collision
documented in ADR 0025 — writing the Terraform side independently and
getting the same answer both times (fix pushgateway to 9096) is itself a
small confirmation that the compose-file fix was the right one, not just
plausible-looking.

## Alternatives considered
- **`docker/docker` provider** (the other namespace on the registry):
  `kreuzwerker/docker` is the far more widely used/maintained one for
  this exact use case (building + running local containers declaratively)
  — chosen without needing a deep bake-off given the clear community
  convention.
- **Terraform Cloud / remote state**: irrelevant for a local-only, single
  operator demo stack — local state file is the right choice, same
  "don't add infrastructure this project doesn't need" discipline as
  ADR 0024's Pushgateway-not-textfile-collector decision.
- **A single giant `main.tf`** instead of one file per service group:
  rejected purely for readability — mirroring `docker-compose.yml`'s own
  per-service comment blocks made the file split obvious and kept each
  file diff-reviewable on its own.

## Consequences
- **Not yet applied.** Verified two ways short of a live daemon: every
  `.tf` file parses as syntactically valid HCL (checked with Python's
  `hcl2` library, not eyeballed), and every resource attribute used here
  is one the provider's own docs actually document (checked against the
  live GitHub-hosted docs, not memory). Neither of those is
  `terraform validate` (which needs the actual provider plugin, itself
  blocked by this sandbox's network allowlist the same way GitHub Actions
  release downloads and the Playwright browser binary were blocked in
  earlier sessions) or a real `terraform apply`. The user's own
  `terraform init && terraform apply` is the real test, and should be
  treated as a debugging pass, likeliest failure points: the Windows
  bind-mount path issue flagged above, and whether the multi-stage
  `kafka-connect` build (which itself downloads two artifacts from GitHub
  Releases / Maven Central mid-build, per ADR 0008) completes inside a
  Terraform-driven `docker build` the same way it does under
  `docker compose build`.
- `13-terraform-apply.gif` stays `[ ]` in `PORTFOLIO_ASSETS.md` until a
  real `terraform apply` run exists to capture.
- `aws/` (the reference-only cloud module infra/terraform/README.md
  originally sketched) is explicitly not built this session — see the
  updated `infra/terraform/README.md` for why, framed as a deliberate
  scope cut, not a dropped TODO.
