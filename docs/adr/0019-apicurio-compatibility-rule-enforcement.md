# ADR 0019: Apicurio compatibility rejection requires an artifact-level rule, not just a global one

Status: Accepted
Date: 2026-08-12

## Context
Task #16's goal: prove that `auto-register=true` doesn't mean "anything goes" — with a compatibility rule configured, an incompatible schema change should be rejected, not silently accepted as a new version. Getting an actual, reproducible rejection took several genuinely wrong turns, each one instructive, documented here rather than smoothed over.

## What didn't work, and why (in order)

**1. Global `COMPATIBILITY: BACKWARD` rule via `/apis/registry/v3/admin/rules`, then reverting `shop.products.price_cents` from `VARCHAR` back to `INTEGER`.** No rejection — connector stayed `RUNNING`. Root cause: the reverted schema was byte-for-byte identical to a schema already registered as version 1, *before* any rule existed. Schema-registry client converters (Apicurio's included) cache schema-content → registered-ID mappings in memory specifically to avoid a network round-trip per message. Since the client already knew "this exact schema is ID 4," it never called the registry's create-version endpoint again — no new registration attempt means no compatibility check ever runs. This wasn't a rule-enforcement failure; it was a test-design flaw (reverting to something already cached instead of testing a genuinely new schema).

**2. Global rule still active, changed `price_cents` to `NUMERIC(10,2)` (Avro: `bytes`/`decimal`, genuinely never registered before, incompatible with the current latest `string` under any Avro promotion).** This registered cleanly as version 3 — no rejection, despite being an unambiguous type change and despite the global rule being confirmed active via `GET /admin/rules/COMPATIBILITY`. This was the real surprise: a global rule, confirmed present, did not block an auto-registration that should have violated it.

**3. Checked whether the compatibility-rule gap was specific to Apicurio's Confluent-compatible layer (`/apis/ccompat/*`)** — fetched Apicurio's own ADR-0001, which explicitly documents "schema registration does NOT enforce BACKWARD — it only applies rules if explicitly configured" as a known limitation of that *specific* layer. Our connectors don't use `/apis/ccompat/*` though (they use `/apis/registry/v2`, per Debezium's own converter docs), so this ADR doesn't directly explain our case — but it confirmed the general pattern (auto-register paths having looser enforcement than the management API implies) is a real, acknowledged category of gap in Apicurio, not something we were imagining.

## What worked
**Added an artifact-specific rule** (`POST /apis/registry/v3/groups/default/artifacts/shop.shop.products.Value/rules`, same `COMPATIBILITY: BACKWARD` config) in addition to the global one. Changed `price_cents` again, this time to `BOOLEAN` (genuinely new, never registered, incompatible with the current latest `bytes`/`decimal`). This time the source connector's **task** (not the connector, which still reported `RUNNING`) went `FAILED`:

```
Caused by: java.lang.RuntimeException: io.apicurio.registry.rest.client.v2.models.Error
  at ...DefaultSchemaResolver.handleAutoCreateArtifact
  at ...KafkaSerializer.serialize
  at ...SerdeBasedConverter.fromConnectData
```

Kafka Connect's default `errors.tolerance=none` means this exception aborted the task outright rather than being swallowed — the same "task state lies at the connector level" trap flagged in ADR 0014, reproduced here in a completely different subsystem months later. Checking `GET /connectors/shop-postgres-source/status` (task-level, not `GET /connectors`) was what actually surfaced this.

## Decision
**Rule enforcement for auto-register needs an artifact-level rule, not just a global one, at least on this Apicurio version/deployment.** The exact mechanism wasn't traced into Apicurio's source (that would be a deeper investigation than this project's scope), but the empirical result across two independent schema changes (NUMERIC not rejected under global-only, BOOLEAN rejected once the artifact-level rule existed) is consistent enough to trust. Going forward, any artifact this project wants genuinely enforced needs its own explicit rule, not just reliance on the global default.

## Consequences
- The portfolio demo (`06-apicurio-rejection` asset) captures this real failure — task-level FAILED status and the actual stack trace — not a staged/cosmetic one.
- `shop-postgres-source`'s task is now in a genuinely FAILED state as a result of this test. Recovery: revert `shop.products.price_cents` to a schema-compatible type (or any previously-registered-compatible shape) and restart the task via `POST /connectors/shop-postgres-source/tasks/0/restart` — tracked as an immediate follow-up, not left broken.
- This is a stronger, more honest data-contracts story than a simple "and then it rejected, ta-da" would have been: it demonstrates the actual production-relevant lesson, which is that auto-register's convenience comes with real gaps, and a team relying on it for enforcement needs to verify — the same "don't trust the framework's happy path, check the real behavior" discipline this whole project has been built on (ADR 0007, 0012, 0013, 0014, 0017).
