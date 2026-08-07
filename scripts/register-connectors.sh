#!/usr/bin/env bash
# Registers the Debezium source and Iceberg sink connectors with the
# Kafka Connect REST API. Run this after `docker compose up -d` once
# kafka-connect is healthy (check: curl localhost:8083/connectors).
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"

echo "Waiting for Kafka Connect at ${CONNECT_URL} ..."
until curl -sf "${CONNECT_URL}/connectors" > /dev/null; do
  sleep 2
done

register() {
  local file="$1"
  local name
  name=$(basename "$file" .json)
  echo "Registering ${name} ..."
  curl -sf -X POST -H "Content-Type: application/json" \
    --data @"${file}" \
    "${CONNECT_URL}/connectors" | python3 -m json.tool || {
      echo "Failed to register ${name} — it may already exist. Checking status:";
      curl -sf "${CONNECT_URL}/connectors/${name}/status" | python3 -m json.tool || true;
    }
}

register "$(dirname "$0")/../kafka-connect/connectors/debezium-postgres-source.json"
register "$(dirname "$0")/../kafka-connect/connectors/iceberg-sink.json"

echo ""
echo "Connector status:"
curl -sf "${CONNECT_URL}/connectors?expand=status" | python3 -m json.tool
