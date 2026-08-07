# Infrastructure as Code — Tier 2 (stretch)

`local/` — Terraform using the Docker provider to provision this entire
compose stack declaratively (`terraform apply` instead of `docker compose up`).

`aws/` — reference-only Terraform module (MSK, EKS, Glue) demonstrating cloud
IaC literacy. Deliberately NOT deployed, to keep this project at $0 — see
docs/adr for the reasoning. Included so the code itself is reviewable.
