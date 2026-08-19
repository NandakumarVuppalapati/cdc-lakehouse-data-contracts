# ADR 0009: Fix Kafka healthcheck broken by its own advertised-listener change

Status: Accepted
Date: 2026-08-08

## Context
After remapping Kafka's host port to 9094 (to avoid a collision with
another project's Kafka on this machine), the broker itself started fine —
logs showed "Kafka Server started," listening on both 9092 and 29092, no
crash — but the container stayed `unhealthy` indefinitely (`FailingStreak: 40`).

`docker inspect ... .State.Health` showed the actual error:
```
Connection to node 1 (localhost/127.0.0.1:9094) could not be established.
```
Root cause: the healthcheck (`kafka-topics.sh --bootstrap-server localhost:9092`)
connects fine initially, but Kafka's admin client protocol then reconnects
using whatever address the broker *advertises* for that listener —
which had been changed to `localhost:9094` (the host-side remapped port) as
part of the same port fix. Port 9094 is a Docker host-to-container mapping;
nothing listens on it inside the container's own network namespace, so the
healthcheck's follow-up connection was always going to fail. This wasn't a
resource or timing issue (as first suspected while waiting ~200s for a
result) — it was broken from the moment the advertised listener changed,
independent of load.

## Decision
Point the healthcheck at the internal `PLAINTEXT` listener
(`localhost:29092`, advertised as `kafka:29092`) instead of `PLAINTEXT_HOST`
(`localhost:9092`, advertised as `localhost:9094`). The internal listener's
advertised address resolves correctly from inside the container; the
host-facing one, by definition, doesn't.

## Consequences
General lesson for this stack: any healthcheck or in-container client must
bootstrap via `PLAINTEXT`/`kafka:29092`, never `PLAINTEXT_HOST`. The host
listener exists solely for tools running outside Docker (a local `kcat`,
etc.) — using it for anything that runs inside a container is a trap,
because its advertised address is deliberately host-oriented and Kafka's
own reconnect-via-advertised-address behavior will surface that mismatch
downstream of the first connection, not immediately.
