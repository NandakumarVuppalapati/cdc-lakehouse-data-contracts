# Infrastructure as Code — Tier 2

`local/` — Terraform (kreuzwerker/docker provider) provisioning this
entire compose stack declaratively: same network name, same container
names, same ports as `docker-compose.yml`, so it's a genuine alternative
provisioner for the identical infra, not a parallel toy stack. See
`docs/adr/0026-terraform-docker-provider.md` for the full design writeup,
including the one real bug (a host-port collision) this exercise caught.

```bash
cd infra/terraform/local
terraform init
terraform apply
```

`docker compose down` first if the compose stack is already running —
both provisioners create resources with the same names, so they can't run
at the same time. `terraform destroy` to tear back down.

By default this creates everything `docker compose up -d` would (the
`dbt` service only runs its harmless `--version` smoke test, same as
compose) but *not* the `great-expectations` one-shot job — mirroring that
service's `profiles: ["jobs"]` gate in the compose file. Pass
`-var run_gx_job=true` to include it.

**Not yet run against a live Docker daemon** — see the ADR's Consequences
section. Every `.tf` file here parses as valid HCL (checked with
`python-hcl2`, see the ADR), and every resource attribute is checked
against the provider's real, current documentation, not guessed — but
"the syntax is valid and the docs say this should work" isn't "a real
`terraform apply` succeeded." That's the next real step, on the user's own
machine.

`aws/` — deliberately not built. The idea (a reference-only Terraform
module for MSK/EKS/Glue, demonstrating cloud IaC literacy without ever
being deployed, to keep this project at $0) is still a reasonable one, but
building a second, materially different Terraform module on top of an
already-large Tier 2 scope (this local module, OpenLineage/Marquez, and a
chaos test all landing in the same session) isn't a good trade right now.
Left here as an explicit, intentional gap rather than a silently dropped
TODO — a genuine next step if this project's scope grows again later, not
a partially-built stub.
