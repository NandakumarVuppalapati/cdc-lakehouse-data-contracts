# dbt Core + the Trino adapter. Pinned versions confirmed compatible against
# dbt docs before writing this (dbt-trino 1.10.x <-> dbt-core 1.11.x) rather
# than guessed — see ADR 0015.
FROM python:3.11-slim

RUN pip install --no-cache-dir dbt-trino==1.10.2

WORKDIR /dbt

# run_with_metrics.py wraps the real `dbt` command (see ADR 0024) — copied
# to /opt, not /dbt, because /dbt/cdc_lakehouse is bind-mounted over at
# runtime (docker-compose.yml) and anything under /dbt itself would be
# shadowed. Transparent: argv passes straight through, exit code is dbt's
# exit code, `docker compose run --rm dbt build/test/run` all work exactly
# as before.
COPY run_with_metrics.py /opt/run_with_metrics.py
ENTRYPOINT ["python3", "/opt/run_with_metrics.py"]
