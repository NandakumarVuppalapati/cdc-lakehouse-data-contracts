# Dagster webserver, with dbt-trino (so DbtCliResource can actually shell
# out to `dbt`) and Great Expectations (so the asset check can run in the
# same process) both installed alongside Dagster itself. Classic
# Definitions-object + `dagster-webserver -f` approach rather than the
# newer `dg`/Components scaffolding — the `dg` CLI is designed around a
# `uv`-managed project directory on a host filesystem, which fights this
# repo's Docker-first pattern; `dagster-webserver -f` is still fully
# supported (confirmed against the current CLI reference, not assumed) and
# needs nothing beyond a plain Python file. See ADR 0022.
FROM python:3.11-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

ENV DAGSTER_HOME=/dagster_home
EXPOSE 3000

# definitions.py is bind-mounted at runtime (see docker-compose.yml), same
# mount-not-bake pattern as dbt/great_expectations elsewhere in this repo.
#
# `dagster dev`, not standalone `dagster-webserver` — found the hard way
# (a "Materialize all" run stuck in Queued forever) that the webserver alone
# doesn't process the run queue; that's the daemon's job. `dagster dev`
# bundles webserver + daemon in one process, which is exactly what a
# single-container local/demo deployment needs. See ADR 0022.
ENTRYPOINT ["dagster", "dev", "-h", "0.0.0.0", "-p", "3000", "-f", "/app/definitions.py"]
