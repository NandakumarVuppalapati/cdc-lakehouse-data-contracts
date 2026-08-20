# Mirrors the `apicurio` service in docker-compose.yml — Avro schema
# registry for contract layer 1, Postgres-backed (own database on the
# shared instance). See ADR 0016.

resource "docker_image" "apicurio" {
  name = "apicurio/apicurio-registry:3.3.1"
}

resource "docker_container" "apicurio" {
  name  = "lakehouse-apicurio"
  image = docker_image.apicurio.image_id

  env = [
    "APICURIO_STORAGE_KIND=sql",
    "APICURIO_STORAGE_SQL_KIND=postgresql",
    "APICURIO_DATASOURCE_URL=jdbc:postgresql://postgres:5432/apicurio_registry",
    "APICURIO_DATASOURCE_USERNAME=lakehouse",
    "APICURIO_DATASOURCE_PASSWORD=lakehouse",
  ]

  ports {
    internal = 8080
    external = 8081
  }
  ports {
    internal = 9000
    external = 9091
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "curl -sf http://localhost:9000/health/ready"]
    interval = "5s"
    timeout  = "5s"
    retries  = 15
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.postgres]
}
