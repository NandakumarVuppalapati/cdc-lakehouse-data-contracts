# Mirrors the `great-expectations` service in docker-compose.yml, which is
# gated behind `profiles: ["jobs"]` there specifically to keep it out of a
# plain `docker compose up -d` (its entrypoint always runs a real checkpoint
# against whatever Gold state exists — no safe no-arg default, see that
# file's comments). `var.run_gx_job` (default false) is this module's mirror
# of that same off-by-default behavior — Terraform has no native concept of
# Compose profiles, so a count-gated resource is the closest honest
# equivalent.

resource "docker_image" "great_expectations" {
  name = "cdc-lakehouse-tf/great-expectations:local"
  build {
    context = "${local.repo_root}/great_expectations"
  }
  triggers = {
    dockerfile_sha1 = filesha1("${local.repo_root}/great_expectations/Dockerfile")
  }
}

resource "docker_container" "great_expectations" {
  count       = var.run_gx_job ? 1 : 0
  name        = "lakehouse-great-expectations"
  image       = docker_image.great_expectations.image_id
  working_dir = "/gx"

  mounts {
    type      = "bind"
    source    = "${local.repo_root}/great_expectations/run_checkpoint.py"
    target    = "/gx/run_checkpoint.py"
    read_only = true
  }

  networks_advanced {
    name = docker_network.lakehouse_net.name
  }

  attach   = true
  must_run = false

  depends_on = [docker_container.dbt]
}
