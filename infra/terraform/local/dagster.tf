# Mirrors the `dagster` service in docker-compose.yml. See ADR 0022 for why
# `dagster dev` (webserver + daemon in one process) rather than the
# standalone webserver.

resource "docker_image" "dagster" {
  name = "cdc-lakehouse-tf/dagster:local"
  build {
    context = "${local.repo_root}/dagster"
  }
  triggers = {
    dockerfile_sha1 = filesha1("${local.repo_root}/dagster/Dockerfile")
  }
}

resource "docker_container" "dagster" {
  name  = "lakehouse-dagster"
  image = docker_image.dagster.image_id

  mounts {
    type   = "bind"
    source = "${local.repo_root}/dagster/definitions.py"
    target = "/app/definitions.py"
  }

  mounts {
    type   = "bind"
    source = "${local.repo_root}/dbt/cdc_lakehouse"
    target = "/dbt/cdc_lakehouse"
  }

  mounts {
    type   = "bind"
    source = "${local.repo_root}/dbt/profiles.yml"
    target = "/dbt/profiles/profiles.yml"
  }

  volumes {
    volume_name    = docker_volume.dagster_home.name
    container_path = "/dagster_home"
  }

  ports {
    internal = 3000
    external = 3000
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  depends_on = [docker_container.trino_init]
}
