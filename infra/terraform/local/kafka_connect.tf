# Mirrors the `kafka-connect` service in docker-compose.yml — built image
# (Debezium + Iceberg sink + Apicurio Avro converter), see
# kafka-connect/Dockerfile and ADR 0005-0008/0016 for why this exact image.

resource "docker_image" "kafka_connect" {
  name = "cdc-lakehouse-tf/kafka-connect:local"
  build {
    context = "${local.repo_root}/kafka-connect"
  }
  triggers = {
    dockerfile_sha1 = filesha1("${local.repo_root}/kafka-connect/Dockerfile")
  }
}

resource "docker_container" "kafka_connect" {
  name  = "lakehouse-kafka-connect"
  image = docker_image.kafka_connect.image_id

  env = [
    "CONNECT_BOOTSTRAP_SERVERS=kafka:29092",
    "CONNECT_GROUP_ID=lakehouse-connect-cluster",
    "CONNECT_CONFIG_STORAGE_TOPIC=lakehouse-connect-configs",
    "CONNECT_OFFSET_STORAGE_TOPIC=lakehouse-connect-offsets",
    "CONNECT_STATUS_STORAGE_TOPIC=lakehouse-connect-status",
    "CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1",
    "CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1",
    "CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1",
    "CONNECT_REST_ADVERTISED_HOST_NAME=kafka-connect",
    "CONNECT_REST_PORT=8083",
    "CONNECT_PLUGIN_PATH=/usr/share/confluent-hub-components,/usr/share/java",
    "CONNECT_KEY_CONVERTER=org.apache.kafka.connect.json.JsonConverter",
    "CONNECT_VALUE_CONVERTER=org.apache.kafka.connect.json.JsonConverter",
    "CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=true",
    "CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=true",
    "CONNECT_LOG4J_ROOT_LOGLEVEL=INFO",
  ]

  ports {
    internal = 8083
    external = 8083
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [
    docker_container.kafka,
    docker_container.postgres,
    docker_container.minio_init,
    docker_container.nessie,
    docker_container.trino_init,
    docker_container.apicurio,
  ]
}
