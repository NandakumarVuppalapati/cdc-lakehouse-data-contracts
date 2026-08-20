# CDC Lakehouse with Data Contracts

> A change-data-capture lakehouse that fails the pipeline — not just warns —
> the moment an upstream schema change breaks a downstream consumer's contract.

Built to explore data reliability at the source instead of downstream: **Debezium**
captures row-level changes from a live PostgreSQL OLTP database, streams them
through **Apache Kafka** into **Apache Iceberg** tables, with **dbt** handling
transformation and a schema-contract layer that enforces backward-compatibility
at three independent points before bad data ever reaches a consumer.

100% free / self-hosted stack. No cloud bill required to run this.

📄 [Architecture](docs/architecture.md) · 🧭 [ADRs](docs/adr) · 📸 [Portfolio assets](PORTFOLIO_ASSETS.md)

## Status

**Tier 0 — pipeline skeleton** — done, verified.
Postgres → Debezium → Kafka → Iceberg (Bronze tables, MinIO + Nessie catalog) → queryable via Trino.

**Tier 1 — contracts, orchestration, CI** — done, verified.
All three contract-enforcement layers (Apicurio, dbt Model Contracts, Great
Expectations), Dagster orchestration, and GitHub Actions CI have each been
brought up and exercised end to end with real data — see
[`PORTFOLIO_ASSETS.md`](PORTFOLIO_ASSETS.md) for the actual captures,
including three genuine, non-staged failures (a rejected schema change, a
bad data value slipping past the shape-only layers and getting caught by
the quality gate, and CI catching the same class of break on a full real
stack it brings up itself — see ADR 0023). Prometheus + Grafana are
code-complete and documented (ADR 0024) but haven't had their first real
run yet — the one piece of Tier 1 still open.

**Tier 2 — lineage, IaC, chaos testing** — code-complete, first live
verification runs pending. Column-level lineage (OpenLineage + Marquez,
ADR 0025), infrastructure-as-code (Terraform, ADR 0026), and a Kafka
broker chaos test with measured recovery (ADR 0027) are all built and
documented against real, confirmed sources — none have been run against a
live stack yet (this project's tooling has no Docker access this session;
see each ADR's Consequences section). Same "built honestly, marked
honestly" status as the Tier 1 observability gap above, not swept under
different language.

## Stack

| Concern | Tool |
|---|---|
| Source OLTP | PostgreSQL 16 |
| CDC capture | Debezium (Kafka Connect) |
| Streaming | Apache Kafka (KRaft mode) |
| Schema contracts (ingestion) | Apicurio Registry |
| Object storage | MinIO |
| Table format | Apache Iceberg |
| Catalog | Nessie |
| Query engine | Trino |
| Transformation | dbt Core (dbt-trino adapter), Model Contracts |
| Data quality | Great Expectations |
| Orchestration | Dagster |
| Observability | Prometheus + Grafana *(built, first real run pending)* |
| CI/CD | GitHub Actions |
| Lineage | OpenLineage + Marquez *(Tier 2 — built, first real run pending)* |
| IaC | Terraform *(Tier 2 — built, first real run pending)* |
| Chaos testing | Kafka broker kill + measured recovery *(Tier 2 — built, first real run pending)* |

## Quickstart

Requires Docker + Docker Compose and ~4GB free RAM for Tier 0.

```bash
git clone <this-repo>
cd cdc-lakehouse-data-contracts
docker compose up -d --build

# Wait for kafka-connect to be healthy, then register the connectors:
./scripts/register-connectors.sh

# Generate some CDC activity:
docker exec -it lakehouse-postgres psql -U lakehouse -d sourcedb \
  -c "INSERT INTO shop.orders (customer_id, status) VALUES (1, 'placed');"

# Query the lakehouse via Trino:
docker exec -it lakehouse-trino trino --catalog iceberg --schema bronze \
  --execute "SELECT * FROM orders LIMIT 10;"
```

MinIO console: http://localhost:9001 (minioadmin / minioadmin)
Nessie API: http://localhost:19120
Kafka Connect REST: http://localhost:8083
Dagster: http://localhost:3000 · Grafana: http://localhost:3001 · Marquez: http://localhost:3002

### Tier 2 extras

```bash
# Column-level lineage: build twice (the 2nd run carries column detail — see ADR 0025)
docker compose run --rm dbt build
docker compose run --rm dbt build

# IaC: provision the same stack declaratively instead of `docker compose up`
docker compose down
cd infra/terraform/local && terraform init && terraform apply

# Chaos test: kill the broker, watch it recover, get a measured recovery time
python chaos/kafka_broker_chaos_test.py
```

## Why these choices

See [`docs/adr/`](docs/adr) for the reasoning behind each non-obvious decision
(Nessie vs Polaris, Dagster vs Airflow, Apicurio vs Confluent Schema Registry,
KRaft vs ZooKeeper) rather than just a tool list.

## License

MIT — see [LICENSE](LICENSE).
