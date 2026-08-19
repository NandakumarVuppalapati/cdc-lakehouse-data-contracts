# GX Core + the Trino SQLAlchemy dialect (from the `trino` PyPI package's
# `[sqlalchemy]` extra). Versions pinned after checking PyPI/docs.greatexpectations.io
# directly (great_expectations 1.20.0, trino 0.338.0, both current as of
# 2026-08-12) rather than guessed — see ADR 0020. Mirrors the dbt/Dockerfile
# pattern already used in this project: thin Python base image, deps baked
# in, no entrypoint script magic.
FROM python:3.11-slim

WORKDIR /gx
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# run_checkpoint.py itself is bind-mounted at runtime (see docker-compose.yml),
# same pattern as dbt/cdc_lakehouse being mounted rather than baked into the
# dbt image — lets the suite/checkpoint definitions change without a rebuild.
ENTRYPOINT ["python", "run_checkpoint.py"]
