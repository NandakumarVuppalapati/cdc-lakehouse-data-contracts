# Same names as docker-compose.yml's network/volumes — this is meant as a
# genuine drop-in alternative provisioner for the identical stack, not a
# parallel shadow copy. Consequence (documented in docs/adr/0026): don't run
# `docker compose up` and `terraform apply` at the same time — `docker
# compose down` first, since both create resources with the same names.

resource "docker_network" "lakehouse_net" {
  name   = "lakehouse-net"
  driver = "bridge"
}

resource "docker_volume" "postgres_data" {
  name = "cdc-lakehouse-tf_postgres_data"
}

resource "docker_volume" "minio_data" {
  name = "cdc-lakehouse-tf_minio_data"
}

resource "docker_volume" "kafka_data" {
  name = "cdc-lakehouse-tf_kafka_data"
}

resource "docker_volume" "dagster_home" {
  name = "cdc-lakehouse-tf_dagster_home"
}

resource "docker_volume" "prometheus_data" {
  name = "cdc-lakehouse-tf_prometheus_data"
}

resource "docker_volume" "grafana_data" {
  name = "cdc-lakehouse-tf_grafana_data"
}

resource "docker_volume" "marquez_db_data" {
  name = "cdc-lakehouse-tf_marquez_db_data"
}
