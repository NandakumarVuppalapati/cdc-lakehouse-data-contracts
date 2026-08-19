# ADR 0021: Recovering a source connector permanently stuck on a historical WAL entry

Status: Accepted
Date: 2026-08-18

## Context
Setting up the Great Expectations genuine-failure demo (write a real typo'd
`status` into `shop.orders`, let it flow through CDC, watch GX catch it —
ADR 0020) exposed that `shop-postgres-source`'s task was still `FAILED`,
weeks after the ADR 0019 Apicurio-rejection test that first broke it. A
prior session's notes claimed this was recovered; it wasn't, or it broke
again identically. Either way, it was still broken now, and it silently
blocked the whole point of the exercise: the typo'd `UPDATE` never reached
Bronze at all, so GX's checkpoint kept passing against stale data.

**Root cause, confirmed by reading the actual stack trace rather than
assuming the earlier "restart the task" fix from ADR 0019 was sufficient:**
a Kafka source connector's task replays the Postgres WAL/replication stream
in order. The specific WAL entry that originally caused the Apicurio
rejection (a `price_cents` write while the column was temporarily `BOOLEAN`,
part of the ADR 0019 demo) is permanently part of that stream. Reverting
`shop.products.price_cents` back to `integer` in Postgres afterward doesn't
erase that historical entry — Debezium still has to serialize and emit it
before it can move on, and that serialization will always produce the same
incompatible Avro schema and hit the same Apicurio rejection, forever. A
plain task restart (`POST .../tasks/0/restart`, what ADR 0019 tried) retries
the same event and fails the same way every time. This is a fundamentally
different failure mode from a transient error — no amount of restarting
fixes it.

**A second, compounding problem discovered while planning the fix:** even
after clearing the stuck WAL position, Postgres's *current* `products`
schema (`int`) would still conflict with Apicurio's *latest registered*
schema for that artifact (`bytes`/`decimal`, from a different ADR 0019 test
step). Fixing problem 1 without also fixing this would just trade one
permanent rejection for another.

## Decision
**Full source-connector reset, using Kafka Connect's Offsets API (KIP-875)
rather than a raw connector delete+recreate.** ADR 0018 already established
that deleting and re-registering a connector under the *same name* resumes
from its previously stored offset (that's what let the Avro cutover skip a
re-snapshot) — which is exactly the wrong behavior here, since the stored
offset points at the poisoned WAL position. The sequence that actually
worked:

1. `PUT /connectors/shop-postgres-source/stop` — stop first; Postgres won't
   let you drop a replication slot that's still attached to an active
   connection.
2. `SELECT pg_drop_replication_slot('lakehouse_debezium_slot')` — discards
   the slot's retained WAL position entirely, so there's nothing left to
   replay from that name.
3. `DELETE /connectors/shop-postgres-source/offsets` — the KIP-875 REST
   endpoint (confirmed supported before running it, not assumed — this
   project's Kafka Connect image is recent enough to have it). Clears
   Kafka Connect's own stored offset for this connector name, which the
   slot drop alone does not touch (they're two independent stores).
4. Attempted `DELETE .../artifacts/shop.shop.products.Value` to clear the
   stale schema history — blocked by Apicurio's own
   `NotAllowedException: Artifact deletion operation is not enabled`
   (a deliberate governance default, not a bug). Fine: deleting the whole
   artifact would have thrown away real history unnecessarily anyway.
5. Attempted `DELETE .../artifacts/shop.shop.products.Value/rules/COMPATIBILITY`
   instead (the narrower, correct fix — remove just the enforcement, keep
   the schema history) — got `RuleNotFoundException`. The artifact-level
   rule ADR 0019 documented adding apparently didn't persist (exact reason
   not traced further; not worth the time given the demo it was for is
   already captured and done). Net effect: nothing was actively blocking
   registration anymore, which was the actual goal.
6. `PUT /connectors/shop-postgres-source/resume` — `202`, and status
   confirmed `RUNNING`/`RUNNING` on the next check.

With no stored offset and no slot, the connector performed a fresh
`snapshot.mode=initial` snapshot of all 4 tables on resume — re-reading
current state (not replaying history), which is exactly what let the
already-corrected `status='shpped'` row surface in Bronze cleanly.

**Unrelated interruption, documented because it cost real time:** midway
through this recovery, the CLI window closed and `docker ps` came back
showing only an unrelated `airflow` project's containers — Docker Desktop
itself had restarted (machine sleep/restart, not something in this
project's control). Confirmed via `docker ps` before assuming anything was
broken again. `docker compose up -d` brought every lakehouse service back
healthy, and Kafka Connect reloaded all 5 connector configs automatically
from its internal topics — no need to re-run `register-connectors.sh`. The
fix already applied (dropped slot, cleared offset) survived the restart
because it lives in Docker volumes, not container state.

**Follow-up, unrelated to the incident itself but caught while writing this
ADR:** the `great-expectations` service had no safe no-argument default the
way `dbt` does (`command: ["--version"]`) — its Dockerfile `ENTRYPOINT`
always runs the real checkpoint. That meant a plain `docker compose up -d`
was silently running a real GX checkpoint against whatever Gold state
happened to exist. Fixed by adding `profiles: ["jobs"]` to the service —
confirmed via search that Compose still runs an explicitly-named service
(`docker compose run --rm great-expectations`) even with an inactive
profile attached, so this doesn't change the documented usage at all, it
just stops the service from running unasked-for during routine `up`.

## Consequences
- The GX genuine-failure demo (`08-great-expectations-failure` asset) is
  now real and verified end-to-end: typo written to Postgres -> fresh
  snapshot -> Bronze -> Silver -> Gold -> GX checkpoint fails with
  `unexpected_count: 1`, `partial_unexpected_list: ["shpped"]` -> recovered
  -> checkpoint green again. Nothing staged.
- A compatibility rule created for a demo is now a known landmine: if this
  project adds more Apicurio compatibility rules for future demos, they
  need either an explicit cleanup step or a documented "this table's
  history is intentionally messy" note, or the next legitimate schema
  change on that table hits the same permanent-rejection trap this ADR just
  recovered from.
- `shop.shop.products.Value`'s schema history is a little unusual as a
  result (four versions: `int` -> `decimal` -> a fresh `int` post-recovery,
  with the `decimal` step's compatibility rule no longer enforced) — worth
  remembering if that artifact's version history ever shows up in a future
  screenshot, so it isn't mistaken for an unexplained inconsistency.
