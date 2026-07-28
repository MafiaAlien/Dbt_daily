---
description: Health-check the local dbt + DuckDB container before starting work
allowed-tools: Read, Bash(docker compose:*), Bash(docker ps:*), Bash(ls:*)
---

Check the practice environment. Report in Chinese, one line per check, pass/fail only —
no essay.

1. Container running: `docker compose ps dbt`. If not, `docker compose up -d dbt`.
2. Connection: `docker compose exec dbt dbt debug`. Report the adapter and dbt versions.
3. Parse: `docker compose exec dbt dbt parse`. This catches duplicate resource names
   across days — the failure mode the `_dNN_` prefix convention exists to prevent.
4. The active day has a `dayNN:` block under `models: dbt_practice:` in
   `dbt_practice/dbt_project.yml`, and its directories exist.
5. Whether `practice.duckdb` exists, and its mtime.
6. Reference project reachable: `docker compose exec -w /workspace_ref dbt dbt debug`,
   and its `dayNN:` block matches the one in `dbt_practice/dbt_project.yml`. A drifted
   materialization there silently changes what the reference run proves. Report
   pass/fail only — do not read anything under `dbt_practice_ref/models/`, which holds
   the reference solution.

If state looks stale or a build is behaving inconsistently, offer — do not run
unprompted — the clean rebuild:

```
docker compose exec dbt bash -c "rm -f practice.duckdb && dbt build --select path:models/dayNN"
```

Never run `dbt` on the host. DuckDB is embedded; dbt and the database share a process.
