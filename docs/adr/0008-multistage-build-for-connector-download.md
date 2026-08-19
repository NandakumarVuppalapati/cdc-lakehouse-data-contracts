# ADR 0008: Multi-stage build for the Iceberg connector download

Status: Accepted
Date: 2026-08-07

## Context
ADR 0007's approach (curl the connector zip, extract with `jar xf` instead
of `unzip`) still failed with exit 127 — command not found — in the same
spot. At that point the pattern was clear: I kept guessing what tools ship
inside `confluentinc/cp-kafka-connect` (unzip? jar? curl itself?) and kept
being wrong, one tool at a time. Continuing to guess individual commands
was going to keep costing a build cycle per guess.

## Decision
Stop depending on anything about the final image's contents for this step.
Download and extract the connector in a separate `alpine:3.20` build stage,
where `apk add curl unzip` is fast, small, and guaranteed to work — then
`COPY --from=` the already-extracted plugin directory into the final
`confluentinc/cp-kafka-connect` image. `COPY` needs nothing from the source
image to exist in the target image; it's just a file copy at the Docker
layer level.

## Consequences
This is strictly more robust and is standard Docker practice for exactly
this situation (fetch/build in one stage, ship only the result in another),
so it should have been the design from the start rather than something
arrived at after three failed single-stage guesses — noted here plainly
rather than glossed over, since "what we'd do differently" is part of the
point of keeping these ADRs. Slightly larger build context (two base image
pulls instead of one) in exchange for zero remaining assumptions about the
runtime image's toolset.
