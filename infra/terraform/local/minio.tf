# Mirrors the `minio` + `minio-init` services in docker-compose.yml.

resource "docker_image" "minio" {
  name = "minio/minio:latest"
}

resource "docker_container" "minio" {
  name    = "lakehouse-minio"
  image   = docker_image.minio.image_id
  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=minioadmin",
    "MINIO_ROOT_PASSWORD=minioadmin",
  ]

  ports {
    internal = 9000
    external = 9000
  }
  ports {
    internal = 9001
    external = 9001
  }

  volumes {
    volume_name    = docker_volume.minio_data.name
    container_path = "/data"
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
    interval = "5s"
    timeout  = "5s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 60
}

resource "docker_image" "minio_mc" {
  name = "minio/mc:latest"
}

# One-shot job: creates the "warehouse" bucket. `attach = true` +
# `must_run = false` is this provider's closest equivalent to Compose's
# `condition: service_completed_successfully` — Terraform waits for the
# container to exit rather than just for it to start. Not verified against
# a live daemon this session (see docs/adr/0026); `docker compose`'s own
# behavior for this exact entrypoint is proven (this project has run it for
# real), only the Terraform *wait* semantics are new/unverified here.
resource "docker_container" "minio_init" {
  name       = "lakehouse-minio-init"
  image      = docker_image.minio_mc.image_id
  entrypoint = ["/bin/sh", "-c"]
  command = [
    "mc alias set local http://minio:9000 minioadmin minioadmin && mc mb --ignore-existing local/warehouse"
  ]

  attach   = true
  must_run = false

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.minio]
}
