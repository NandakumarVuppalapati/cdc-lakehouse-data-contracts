# Mirrors the `dbt` service in docker-compose.yml. Like that service, this
# resource only runs the harmless `--version` smoke test by default — real
# invocations (`dbt build`, `dbt test`, ...) are ad hoc `docker compose run`
# / `docker exec` calls, not something "up"-shaped infra provisioning
# should model. See ADR 0026 for that scope boundary.

resource "docker_image" "dbt" {
  name = "cdc-lakehouse-tf/dbt:local"
  build {
    context = "${local.repo_root}/dbt"
  }
  triggers = {
    dockerfile_sha1 = filesha1("${local.repo_root}/dbt/Dockerfile")
  }
}

resource "docker_container" "dbt" {
  name       = "lakehouse-dbt"
  image      = docker_image.dbt.image_id
  command    = ["--version"]
  working_dir = "/dbt/cdc_lakehouse"

  env = [
    "OPENLINEAGE_URL=http://marquez-api:5000",
    "OPENLINEAGE_NAMESPACE=cdc_lakehouse",
  ]

  mounts {
    type   = "bind"
    source = "${local.repo_root}/dbt/cdc_lakehouse"
    target = "/dbt/cdc_lakehouse"
  }

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/dbt/profiles.yml"
    target    = "/root/.dbt/profiles.yml"
    read_only = true
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  attach   = true
  must_run = false

  depends_on = [docker_container.trino_init, docker_container.marquez_api]
}
