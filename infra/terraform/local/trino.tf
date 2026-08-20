# Mirrors the `trino` + `trino-init` services in docker-compose.yml. Host
# port remapped to 8082 (8080 is taken by another local project — same
# note as the compose file).

resource "docker_image" "trino" {
  name = "trinodb/trino:483"
}

resource "docker_container" "trino" {
  name  = "lakehouse-trino"
  image = docker_image.trino.image_id

  ports {
    internal = 8080
    external = 8082
  }

  mounts {
    type   = "bind"
    source = "${local.repo_root}/trino/catalog"
    target = "/etc/trino/catalog"
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  healthcheck {
    test     = ["CMD-SHELL", "curl -f http://localhost:8080/v1/info || exit 1"]
    interval = "10s"
    timeout  = "10s"
    retries  = 10
  }

  wait         = true
  wait_timeout = 90

  depends_on = [docker_container.nessie, docker_container.minio_init]
}

# One-shot: creates the bronze/silver/gold Iceberg namespaces. See ADR 0011
# and trino-init/init-schemas.sh — the real fix for "namespace must exist"
# races.
resource "docker_container" "trino_init" {
  name       = "lakehouse-trino-init"
  image      = docker_image.trino.image_id
  entrypoint = ["/bin/sh", "/init-schemas.sh"]

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/trino-init/init-schemas.sh"
    target    = "/init-schemas.sh"
    read_only = true
  }

  attach   = true
  must_run = false

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.trino]
}
