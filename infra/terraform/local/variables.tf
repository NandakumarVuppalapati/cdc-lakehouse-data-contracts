# See docs/adr/0026 for why these are variables instead of hardcoded, and
# for the Windows/Docker-Desktop path caveat this project could not verify
# against a live daemon this session (no Docker access from the sandbox
# that wrote this).

variable "docker_host" {
  description = <<-EOT
    Docker daemon socket. Docker Desktop on Windows defaults to a named
    pipe; on macOS/Linux it's usually the default unix socket the provider
    already assumes when this is left empty. Override via terraform.tfvars
    or -var if your setup differs (e.g. a WSL2 docker context).
  EOT
  type        = string
  default     = "npipe:////./pipe/docker_engine"
}

variable "repo_root" {
  description = "Absolute path to the repo root, so build contexts (kafka-connect/, dbt/, etc.) resolve correctly no matter where `terraform apply` is run from. Defaults to two directories up from this module."
  type        = string
  default     = null
}

variable "run_gx_job" {
  description = <<-EOT
    Whether to also create the great-expectations one-shot container.
    Mirrors docker-compose.yml's `profiles: ["jobs"]` on that service,
    which keeps it out of a plain `docker compose up -d` — Terraform has
    no direct equivalent of Compose profiles, so this variable is the
    closest honest mirror: off by default, same as compose.
  EOT
  type        = bool
  default     = false
}

locals {
  # Forward-slash everywhere regardless of host OS — the Docker daemon API
  # (and Docker Desktop's own path translation on Windows) expects
  # forward-slash paths for bind mounts; Terraform's own path functions can
  # return backslashes on native Windows. Defensive, not fully verified —
  # see the Windows caveat in docs/adr/0026.
  repo_root = replace(coalesce(var.repo_root, abspath("${path.module}/../..")), "\\", "/")
}
