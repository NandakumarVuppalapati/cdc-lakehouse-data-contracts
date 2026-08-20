# Provider version confirmed against the Terraform Registry (kreuzwerker/docker
# 4.5.0, latest as of 2026-08-20 — see docs/adr/0026) before pinning, not
# guessed.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "4.5.0"
    }
  }
}

provider "docker" {
  host = var.docker_host
}
