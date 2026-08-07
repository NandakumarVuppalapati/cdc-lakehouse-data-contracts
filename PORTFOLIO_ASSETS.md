# Portfolio Asset Checklist

Purpose: capture proof as we build, not scramble for screenshots after the
fact. Every item below gets saved into `docs/assets/` using the naming
convention `NN-short-name.ext` (numbered so they sort in build order). The
personal portfolio site pulls directly from this folder — nothing there is
staged or faked.

Legend: `[ ]` not captured yet · `[x]` captured · file name is the target filename once captured.

## Tier 0 — pipeline skeleton

- [ ] `01-architecture-diagram.png` — exported version of docs/architecture.md's Mermaid diagram
- [ ] `02-docker-compose-up.gif` — terminal recording of `docker compose up -d --build` succeeding end to end
- [ ] `03-cdc-event-flow.gif` — INSERT into Postgres on the left, corresponding row appearing in Trino query on the right (split screen or two terminal panes)
- [ ] `04-minio-console-warehouse.png` — MinIO console showing the Iceberg warehouse bucket with real table files
- [ ] `05-nessie-commit-log.png` — Nessie's commit history showing table changes over time (the git-like versioning payoff)

## Tier 1 — contracts, orchestration, CI

- [ ] `06-apicurio-rejection.png` — Apicurio Registry rejecting an incompatible schema, with the error message visible
- [ ] `07-dbt-contract-failure.png` — terminal output of `dbt run` failing with a Model Contract violation, error text visible
- [ ] `08-great-expectations-failure.png` — a Great Expectations checkpoint failing with the specific expectation that tripped
- [ ] `09-dagster-lineage-graph.png` — Dagster's asset graph showing the full pipeline as connected, contracted assets
- [ ] `10-ci-breaking-change-test.png` or `.gif` — the GitHub Actions run log where the pipeline is deliberately broken and CI catches it (this is the single most important asset — it's the proof for the whole project's thesis)
- [ ] `11-grafana-dashboard.png` — Grafana dashboard showing consumer lag / run duration / contract-violation count metrics

## Tier 2 — stretch (capture whichever get built)

- [ ] `12-openlineage-graph.png` — column-level lineage view in Marquez
- [ ] `13-terraform-apply.gif` — `terraform apply` provisioning the local stack declaratively
- [ ] `14-chaos-test-recovery.png` — logs showing the pipeline recovering after a killed Kafka broker / corrupted message, with the recovery time noted

## Narrative assets (write once the above exist, not before)

- [ ] `demo-video.mp4` — 2-3 min walkthrough: problem -> architecture -> the moment a breaking change gets caught -> what changes at 10x scale
- [ ] `case-study.md` — the write-up referenced in the plan doc: why 3 contract layers, what trade-off each tool choice implied, what you'd do differently at scale
- [ ] key metrics for the portfolio site's stat callouts, e.g.:
  - CDC event -> queryable-in-Iceberg latency (p50/p95)
  - number of independent failure points a bad schema change is caught at
  - CI run time for the full breaking-change test

## How this feeds the portfolio site

The `portfolio-site/` repo's `data/projects.json` has an `assets` array per
project that points at filenames from this list. Drop a captured file into
`docs/assets/` here, copy it (or symlink) into the portfolio repo's
`assets/cdc-lakehouse/` folder, tick the box above, and the site picks it up
on next deploy — no code changes needed for new screenshots.
