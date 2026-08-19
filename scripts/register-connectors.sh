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

CONNECTORS_DIR="$(dirname "$0")/../kafka-connect/connectors"

register "${CONNECTORS_DIR}/debezium-postgres-source.json"
# One sink connector per table — see ADR 0012 for why this replaced a single
# multi-topic connector (that pattern isn't actually supported without a
# route-field and caused real record misrouting between tables).
register "${CONNECTORS_DIR}/iceberg-sink-customers.json"
register "${CONNECTORS_DIR}/iceberg-sink-products.json"
register "${CONNECTORS_DIR}/iceberg-sink-orders.json"
register "${CONNECTORS_DIR}/iceberg-sink-order-items.json"

echo ""
echo "Connector status:"
curl -sf "${CONNECT_URL}/connectors?expand=status" | python3 -m json.tool
