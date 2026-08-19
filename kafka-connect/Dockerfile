# Kafka Connect image = Confluent's Kafka Connect worker (ships the
# confluent-hub CLI) + the Debezium Postgres source connector (via
# confluent-hub) + the Iceberg sink connector (downloaded in a separate
# build stage — see below for why not directly in the final image).
#
# --- Why this image, after four failed attempts ---
# Attempt 1: debezium/connect:2.7 — tag doesn't exist. See ADR 0005.
# Attempt 2: quay.io/debezium/connect:3.6.0.Final + curl the Iceberg
#   "runtime" zip from Maven Central — that artifact isn't published
#   there. See ADR 0006.
# Attempt 3: confluentinc/cp-kafka-connect + `confluent-hub install
#   tabular/iceberg-kafka-connect` — that Confluent Hub listing is
#   delisted, not just deprecated. See ADR 0007.
# Attempt 4: curl the connector straight from its real GitHub release,
#   then `unzip` (exit 127, not installed) — switched to `jar xf` (exit
#   127 again). Turns out this Confluent base image doesn't reliably have
#   curl on PATH either — every one of these tools is an assumption about
#   what's inside someone else's base image, and this one kept being wrong.
# This attempt: stop guessing what's inside confluentinc/cp-kafka-connect.
#   Download and unpack the connector in a throwaway `alpine` build stage
#   instead, where curl/unzip are one `apk add` away and guaranteed to
#   work, then COPY the already-extracted files into the final image.
#   COPY doesn't need curl, unzip, or jar to exist in the target image at
#   all. See ADR 0008.

# --- Stage 1: download + extract the Iceberg sink connector ---
FROM alpine:3.20 AS iceberg-connector-downloader

ARG ICEBERG_KAFKA_CONNECT_VERSION=0.6.19

RUN apk add --no-cache curl unzip \
    && curl -fSL -o /tmp/iceberg-kafka-connect-runtime.zip \
       "https://github.com/databricks/iceberg-kafka-connect/releases/download/v${ICEBERG_KAFKA_CONNECT_VERSION}/iceberg-kafka-connect-runtime-${ICEBERG_KAFKA_CONNECT_VERSION}.zip" \
    && mkdir -p /plugin/iceberg-kafka-connect \
    && unzip /tmp/iceberg-kafka-connect-runtime.zip -d /plugin/iceberg-kafka-connect \
    && rm /tmp/iceberg-kafka-connect-runtime.zip

# --- Stage 2: download + extract the Apicurio Avro Kafka Connect converter ---
# Same alpine-downloader pattern as stage 1, reused rather than reinvented —
# this base image's curl/unzip availability is exactly as unreliable as it
# was for the Iceberg connector (see the attempt log above). Pulled straight
# from Maven Central (confirmed this artifact/version actually exists there
# before writing this, same discipline as ADR 0006's lesson about assuming
# an artifact is published somewhere it isn't).
FROM alpine:3.20 AS apicurio-converter-downloader

ARG APICURIO_CONVERTER_VERSION=3.3.1

RUN apk add --no-cache curl unzip \
    && curl -fSL -o /tmp/apicurio-connect-converter.zip \
       "https://repo1.maven.org/maven2/io/apicurio/apicurio-registry-distro-connect-converter/${APICURIO_CONVERTER_VERSION}/apicurio-registry-distro-connect-converter-${APICURIO_CONVERTER_VERSION}.zip" \
    && mkdir -p /plugin/apicurio-registry-connect-converter \
    && unzip /tmp/apicurio-connect-converter.zip -d /plugin/apicurio-registry-connect-converter \
    && rm /tmp/apicurio-connect-converter.zip

# --- Stage 3: the actual Kafka Connect worker image ---
FROM confluentinc/cp-kafka-connect:8.2.2

# Debezium's Postgres connector, distributed via Confluent Hub — this one
# installs cleanly (confirmed working).
RUN confluent-hub install --no-prompt debezium/debezium-connector-postgresql:latest

# Iceberg sink connector, already downloaded and extracted in stage 1.
# connector.class is io.tabular.iceberg.connect.IcebergSinkConnector
# (package name predates the project's move to the databricks org).
COPY --from=iceberg-connector-downloader /plugin/iceberg-kafka-connect /usr/share/confluent-hub-components/iceberg-kafka-connect

# Apicurio's Avro converter, already downloaded and extracted in stage 2.
# converter class is io.apicurio.registry.utils.converter.AvroConverter
# (confirmed against Debezium's own Avro serialization docs — see ADR 0016).
COPY --from=apicurio-converter-downloader /plugin/apicurio-registry-connect-converter /usr/share/confluent-hub-components/apicurio-registry-connect-converter
