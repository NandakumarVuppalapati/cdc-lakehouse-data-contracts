# Portfolio Asset Checklist

Purpose: capture proof as we build, not scramble for screenshots after the
fact. Every item below gets saved into `docs/assets/` using the naming
convention `NN-short-name.ext` (numbered so they sort in build order). The
personal portfolio site pulls directly from this folder — nothing there is
staged or faked.

Legend: `[ ]` not captured yet · `[x]` captured · file name is the target filename once captured.

## Tier 0 — pipeline skeleton

- [x] `01-architecture-diagram.svg` — hand-built diagram matching docs/architecture.md's flow, colored by Tier 0 (live) vs Tier 1 (planned), with the three contract-enforcement layers annotated
- [x] `02-docker-compose-up.jpg` — terminal screenshot of `docker compose up -d` succeeding end to end, all 8 services healthy/running
- [x] `03-cdc-event-flow.jpg` — INSERT into Postgres, then the new row appearing in the Trino query with `op:"c"`, captured in one screenshot
- [x] `04-minio-console-warehouse.jpg` — MinIO console showing the Iceberg warehouse bucket with real table files
- [x] `05-nessie-commit-log.jpg` — Nessie's commit history showing table changes over time (the git-like versioning payoff)

## Tier 1 — contracts, orchestration, CI

- [x] `06-apicurio-rejection.jpg` — Kafka Connect task FAILED after an incompatible Avro schema change (price_cents INTEGER -> BOOLEAN) hit an Apicurio artifact-level BACKWARD compatibility rule; full stack trace visible, task-level status (not connector-level) as the tell
- [x] `07-dbt-contract-failure.jpg` — terminal output of `dbt run` failing with a Model Contract violation, error text visible
- [x] `08-great-expectations-failure.jpg` — `expect_column_values_to_be_in_set` on `gold_order_summary.status` failing after a typo'd status (`'shpped'`) was written directly to Postgres; dbt's contract (layer 2) let it through untouched since it only checks type, not allowed values
- [x] `09-dagster-lineage-graph.jpg` — Dagster's asset lineage view showing Silver -> Gold with real materialization timestamps and asset-check pass counts (3/3, 4/4) after a genuine "Materialize all" run
- [x] `09b-dagster-asset-checks.jpg` (bonus) — the `gold_order_summary` Checks tab: the blocking GX check plus 3 dbt-derived checks, all succeeded, full `gx_result` visible
- [x] `10-ci-breaking-change-test.jpg` — real GitHub Actions run (github.com/NandakumarVuppalapati/cdc-lakehouse-data-contracts/actions/runs/32380180469), `full-pipeline` job succeeded in 5m 33s: full stack up, real CDC flow, happy-path pass, then the injected `'shpped'` typo correctly caught by Great Expectations while dbt's shape-only contract correctly let it through — this is the single most important asset, and it's a real run, not a mockup
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
