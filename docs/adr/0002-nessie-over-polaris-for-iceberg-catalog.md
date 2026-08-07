# ADR 0002: Nessie over Polaris for the Iceberg catalog

Status: Accepted
Date: 2026-08-07

## Context
Apache Iceberg needs a catalog to track table metadata. The two leading
open-source, self-hostable options in 2026 are Project Nessie and Apache
Polaris (incubating). Both are free, both integrate with Trino/Spark.

## Decision
Use Nessie for Tier 0/1.

## Alternatives considered
**Apache Polaris** — stronger centralized RBAC/governance model, better fit
if this were a multi-team platform with many consumers needing fine-grained
access control. Overkill for a single-developer project, and its governance
strengths aren't demonstrable without multiple real consumers.

**AWS Glue / Hive Metastore** — Glue isn't free outside AWS's tier limits and
ties the project to a cloud bill; Hive Metastore is heavier to operate for
no benefit here.

## Consequences
Nessie's git-like branch/tag/merge model lets us demonstrate testing a schema
change on a branch before merging to `main` — a concrete, visual way to show
"safe schema evolution" in a demo GIF, which Polaris doesn't offer. Trade-off:
Nessie's RBAC is weaker, which we accept since this isn't a multi-tenant system.
If this project grows a real access-control story later, this decision gets
revisited (see ADR template for that future entry).
