# Mirrors the `nessie` service in docker-compose.yml — JDBC version store on
# the shared postgres instance's dedicated `nessie` database (created by
# postgres/00-create-nessie-db.sql). See ADR 0013 for why JDBC over RocksDB.

resource "docker_image" "nessie" {
  name = "ghcr.io/projectnessie/nessie:latest"
}

resource "docker_container" "nessie" {
  name  = "lakehouse-nessie"
  image = docker_image.nessie.image_id

  env = [
    "NESSIE_VERSION_STORE_TYPE=JDBC",
    "QUARKUS_DATASOURCE_DB_KIND=postgresql",
    "QUARKUS_DATASOURCE_JDBC_URL=jdbc:postgresql://postgres:5432/nessie",
    "QUARKUS_DATASOURCE_USERNAME=lakehouse",
    "QUARKUS_DATASOURCE_PASSWORD=lakehouse",
  ]

  ports {
    internal = 19120
    external = 19120
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  # Quarkus management port (9000), not 19120 — no readiness signal on the
  # main port. Same real fix as ADR 0013.
  healthcheck {
    test     = ["CMD-SHELL", "curl -sf http://localhost:9000/q/health/ready"]
    interval = "5s"
    timeout  = "5s"
    retries  = 15
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.postgres]
}
