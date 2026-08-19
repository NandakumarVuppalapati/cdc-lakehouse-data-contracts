#!/bin/sh
# Creates the Iceberg namespaces (bronze, silver, gold) that Nessie requires
# to exist before any table can be created in them (ADR 0011).
#
# Written as a real script, not an inline docker-compose entrypoint string —
# the retry logic below needs a shell variable and a loop, and cramming that
# into a YAML folded scalar means fighting three layers of escaping at once
# (YAML itself, Docker Compose's $/$$ variable interpolation, and POSIX
# shell quoting) for no real benefit. A mounted script is plain shell,
# readable, and side-steps all of that.
#
# Retries each CREATE SCHEMA statement rather than just trusting the
# `trino` service's healthcheck (docker-compose.yml) to mean "ready". Trino
# can return 200 on /v1/info while its coordinator is still internally in
# SERVER_STARTING_UP — confirmed as a known Trino behavior (not specific to
# this stack), see ADR 0017. A query issued in that window fails with
# "No nodes available to run query" even though the HTTP healthcheck
# already passed.
set -u

run_with_retry() {
  statement="$1"
  attempt=0
  max_attempts=12
  while [ "$attempt" -lt "$max_attempts" ]; do
    if trino --server http://trino:8080 --catalog iceberg --execute "$statement"; then
      return 0
    fi
    attempt=$((attempt + 1))
    echo "trino not ready yet (attempt $attempt/$max_attempts), retrying in 5s..."
    sleep 5
  done
  echo "trino never became ready after $max_attempts attempts ($statement) — giving up."
  return 1
}

run_with_retry "CREATE SCHEMA IF NOT EXISTS bronze" \
  && run_with_retry "CREATE SCHEMA IF NOT EXISTS silver" \
  && run_with_retry "CREATE SCHEMA IF NOT EXISTS gold"
