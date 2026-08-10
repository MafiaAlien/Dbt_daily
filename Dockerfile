FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
# Pinned deliberately. Unpinned, any `docker compose build` silently moves the adapter,
# and the reference project would end up running under a different one than dbt_practice
# — /review's three-way compare would then read a version difference as a code difference.
# Bump these on purpose, between days, never mid-day. Current: dbt-core 1.12.0 arrives as
# a dependency of dbt-duckdb; pin it here too if it ever drifts.
RUN pip install --no-cache-dir \
      dbt-duckdb==1.10.1 \
      duckdb==1.5.5
WORKDIR /workspace
ENTRYPOINT ["bash"]