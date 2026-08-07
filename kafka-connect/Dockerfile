# Kafka Connect image = Debezium Connect (Postgres source connector already
# bundled) + the Apache Iceberg Kafka Connect Sink connector layered on top.
#
# Debezium Connect base image already ships:
#   - Debezium Postgres connector (io.debezium.connector.postgresql.PostgresConnector)
#
# We add:
#   - Apache Iceberg Kafka Connect runtime (sink connector + Iceberg core/AWS libs)
#
# Versions pinned deliberately — bump these consciously, not accidentally.
FROM debezium/connect:2.7

ARG ICEBERG_VERSION=1.6.1
ARG ICEBERG_KAFKA_CONNECT_VERSION=1.6.1

USER root

# Apache Iceberg publishes a runtime fat-jar bundle for Kafka Connect that
# includes the connector + Iceberg core + AWS/S3 filesystem support.
RUN curl -fSL -o /tmp/iceberg-kafka-connect-runtime.zip \
    "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-kafka-connect-runtime/${ICEBERG_KAFKA_CONNECT_VERSION}/iceberg-kafka-connect-runtime-${ICEBERG_KAFKA_CONNECT_VERSION}.zip" \
    && unzip /tmp/iceberg-kafka-connect-runtime.zip -d /kafka/connect/iceberg-kafka-connect \
    && rm /tmp/iceberg-kafka-connect-runtime.zip

USER kafka
