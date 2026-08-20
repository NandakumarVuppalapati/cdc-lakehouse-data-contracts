# Mirrors the `kafka` service in docker-compose.yml — KRaft mode, single
# node broker+controller, host port remapped to 9094. See that file's
# comments (and ADR 0010) for why the transaction-log replication settings
# are forced to 1 on a single-broker cluster.

resource "docker_image" "kafka" {
  name = "apache/kafka:4.3.1"
}

resource "docker_container" "kafka" {
  name  = "lakehouse-kafka"
  image = docker_image.kafka.image_id

  env = [
    "KAFKA_NODE_ID=1",
    "KAFKA_PROCESS_ROLES=broker,controller",
    "KAFKA_LISTENERS=PLAINTEXT://:29092,CONTROLLER://:29093,PLAINTEXT_HOST://:9092",
    "KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka:29092,PLAINTEXT_HOST://localhost:9094",
    "KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT",
    "KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER",
    "KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka:29093",
    "KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT",
    "KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1",
    "KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0",
    "KAFKA_AUTO_CREATE_TOPICS_ENABLE=true",
    "KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1",
    "KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1",
  ]

  ports {
    internal = 9092
    external = 9094
  }

  volumes {
    volume_name    = docker_volume.kafka_data.name
    container_path = "/var/lib/kafka/data"
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  # Must use the internal listener (29092) — see the equivalent comment in
  # docker-compose.yml for why PLAINTEXT_HOST/9092 doesn't work here.
  healthcheck {
    test     = ["CMD-SHELL", "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:29092 --list"]
    interval = "10s"
    timeout  = "10s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 120
}
