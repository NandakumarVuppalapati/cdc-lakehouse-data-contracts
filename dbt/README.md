# dbt project — Tier 1 (coming next)

Will contain: `cdc_lakehouse/` dbt project targeting Trino, medallion models
(Bronze -> Silver -> Gold), with `contract: {enforced: true}` on Silver/Gold
models so `dbt run` fails the build on a breaking schema change. This is
contract-enforcement layer #2 (see docs/architecture.md).
