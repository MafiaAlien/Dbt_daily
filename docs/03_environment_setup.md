# Environment Setup — dbt Core + DuckDB in Docker

**Single practice repo reused across all days.** Days are separated by subdirectory
under `models/` and `seeds/`, not by separate dbt projects. Rationale and the
alternatives considered are in "Day scoping" below.

The one split that *is* by project is Neil's code vs the generated reference solution —
see "The reference-solution project". That split is forced by dbt's per-project name
uniqueness, not by day scoping.

## Two environments, kept isolated

| Environment | Purpose | Adapter | Location |
|---|---|---|---|
| Local practice | All daily practice problems (Day 1 onward) | `dbt-duckdb` | Docker container, this repo |
| Databricks companion | Following dbt Learn course demos only | `dbt-databricks` | Separate venv + separate project dir |

Never share `profiles.yml`, project config, or models between the two. Materialization
semantics differ (DuckDB file DB vs Delta on a warehouse), and the practice traps are
written against DuckDB behaviour.

## How dbt talks to DuckDB (important mental model)

DuckDB is **embedded / in-process** — there is no server and no network port. The
`dbt-duckdb` adapter opens the `.duckdb` file directly inside dbt's own process.
Consequences:

- dbt and DuckDB must live in the **same container**. A "DuckDB container" that dbt
  connects to over the network does not exist.
- The connection is a **file path**, not a connection string.
- `practice.duckdb` is a single file on the host via volume mount, which is why it is
  disposable (`rm practice.duckdb && dbt build`).

## Files

`Dockerfile`
```dockerfile
FROM python:3.11-slim
RUN pip install --no-cache-dir dbt-duckdb duckdb
WORKDIR /workspace
ENTRYPOINT ["bash"]
```

`docker-compose.yml`
```yaml
# Pinned so the compose project name is independent of the directory name.
# Renaming the repo folder then produces no orphaned containers or images.
name: dbt_daily

services:
  dbt:
    build: .
    volumes:
      - ./dbt_practice:/workspace
      # Reference-solution project, run with `docker compose exec -w /workspace_ref dbt …`
      - ./dbt_practice_ref:/workspace_ref
      - ./profiles.yml:/root/.dbt/profiles.yml:ro
    stdin_open: true
    tty: true
```

Without the `name:` key, compose derives the project name from the directory name, so
renaming the repo silently strands the old containers and image — they keep running
against the same bind-mounted `practice.duckdb`, and DuckDB is single-writer.

`profiles.yml` is mounted `:ro`. dbt only reads it; a read-only mount means a stray
command inside the container cannot rewrite the host copy.

`profiles.yml` (mounted to `/root/.dbt/profiles.yml`)
```yaml
dbt_practice:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: './practice.duckdb'
      threads: 4

# Reference solutions. Separate DB file so a reference run never overwrites Neil's
# relations. Path is relative to the cwd, i.e. /workspace_ref.
dbt_practice_ref:
  target: dev
  outputs:
    dev:
      type: duckdb
      path: './practice_ref.duckdb'
      threads: 4
```

Two profiles, one file. The profile a project uses is chosen by its own
`profile:` key in `dbt_project.yml`, not by anything at the command line.

`dbt_practice/dbt_project.yml`
```yaml
name: dbt_practice
version: '1.0.0'
profile: dbt_practice

model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
analysis-paths: ["analyses"]
macro-paths: ["macros"]

target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"

models:
  dbt_practice:
    day1:
      staging:
        +materialized: view
      marts:
        +materialized: table
    day2:
      staging:
        +materialized: view
      marts:
        +materialized: table

seeds:
  dbt_practice:
    +quote_columns: false
```

The `day1:` / `day2:` blocks above are illustrative — they show the shape after two days
have been scaffolded. In the live file `models: dbt_practice:` starts empty and
`/newday` appends one block per day.

Note: `seeds:` is a **top-level key**, sibling to `models:` — not nested under it.
Seeds have **no materialization config**; they are always loaded as tables. What is
configurable per-day: `+schema`, `+column_types`, `+quote_columns`, `+enabled`.

**On the `*-paths` keys:** every one of them above is dbt's own default written out
explicitly — `model-paths` defaults to `["models"]`, `test-paths` to `["tests"]`,
`analysis-paths` to `["analyses"]`, `macro-paths` to `["macros"]`, and `snapshot-paths`
to `["snapshots"]`. Omitting a key does not disable the directory. In particular the
Day 7 / Day 8 snapshot problems need **only** a `snapshots/` directory to exist; no
`snapshot-paths` entry is required. Declaring these keys is a readability choice, not a
functional one — the one time it matters is when a path differs from the default.

Each new day **adds** a `dayN` block; previous blocks stay so any earlier day can be
rebuilt on demand.

## Day scoping

### Structure

```
dbt_practice/
├── dbt_project.yml
├── models/
│   ├── day1/
│   │   ├── staging/       (stg_d1_*.sql + schema.yml)
│   │   ├── intermediate/  (int_d1_*.sql, Medium problems onward)
│   │   └── marts/         (fct_d1_* / dim_d1_* + schema.yml)
│   └── day2/
│       ├── staging/
│       └── marts/
├── seeds/
│   ├── day1/              (raw_d1_*.csv)
│   └── day2/
├── snapshots/             (SCD2 problems)
├── macros/
├── tests/                 (singular tests)
└── archive/               (retired days; NOT in model-paths, so dbt ignores it)
```

### Naming uniqueness rule (hard constraint)

dbt requires **model and seed names to be unique across the entire project**,
regardless of directory. `models/day1/staging/stg_orders.sql` and
`models/day2/staging/stg_orders.sql` is a compile error, not a warning.

Therefore every resource carries a day prefix:

- seeds: `raw_d2_orders.csv`
- staging: `stg_d2_orders.sql`
- intermediate: `int_d2_order_items.sql`
- marts: `fct_d2_daily_revenue.sql`
- refs: `{{ ref('stg_d2_orders') }}`, `{{ source(...) }}` unaffected

### Alternatives considered (and why rejected as default)

- **One `dbt init` project per day** — rejected: no cross-day DAG, no realistic
  multi-layer project, breaks Day 3 (config precedence) and Day 12 (refactoring a
  legacy script into layers), fragments `profiles.yml`, makes the post-Block-3
  mixed-topic review day painful.
- **Reuse names + move finished days to `archive/`** — acceptable fallback (dbt ignores
  `archive/` since it is outside `model-paths`), but retired days stop being part of the
  live DAG and must be moved back for mixed review.
- **Flat layer dirs + `tags=['dayN']` instead of day dirs** — viable, and lets
  `staging: +materialized: view` be written once; still requires the name prefix.
  Kept as an option, not the default.

**Exception:** a problem that needs genuinely different *project-level* configuration
(e.g. Day 13, dev vs prod targets and schemas) may get its own project directory.

## The reference-solution project

Stage 4 executes the Stage 2 reference solution. It cannot run inside `dbt_practice/`:
model names are unique **per project**, so the reference's `stg_dNN_customers.sql` and
Neil's would collide and `dbt parse` would fail for both. The two ways out are renaming
the reference's models or giving it its own project; renaming means editing generated
code, and an edit is exactly how a real bug in the reference quietly disappears before
Stage 4 can score it. So: its own project.

```
dbt_practice_ref/
├── dbt_project.yml        (name: dbt_practice_ref, profile: dbt_practice_ref)
├── models/dayNN/          transcribed verbatim from days/dayNN/reference_solution.md
├── seeds/dayNN/           cp -R from dbt_practice/seeds/dayNN/  (gitignored copies)
└── practice_ref.duckdb    its own database file
```

- Mounted at `/workspace_ref` in the **same** container — one dbt install, two projects.
- Its `dayNN:` model config blocks must mirror `dbt_practice/dbt_project.yml`. The
  reference is generated against the materializations the problem states; if the two
  drift, the reference run stops proving anything. `/newday` writes both blocks.
- Separate `.duckdb` file, so a reference run never overwrites the relations Neil's run
  produced — both sets of results stay queryable during the three-way compare.
- Written only by `/review NN` phase 2, and only by transcription. Nothing in
  `dbt_practice_ref/models/` is ever authored or corrected in this repo.

```bash
cp -R dbt_practice/seeds/day1 dbt_practice_ref/seeds/day1
docker compose exec -w /workspace_ref dbt dbt build --select path:models/day1
duckdb dbt_practice_ref/practice_ref.duckdb        # inspect reference results
```

## Command cheat sheet

```
docker compose up -d dbt              # start persistent container
docker compose exec dbt bash          # shell into it
docker compose stop / start dbt       # keep between sessions

dbt debug                             # verify connection
dbt seed  --select path:seeds/day2    # load only this day's seeds
dbt run   --select path:models/day2   # build only this day's models
dbt build --select path:models/day2   # seed+run+test, day-scoped
dbt build --select tag:day2           # same, if tagging instead of paths
dbt run   --select stg_d2_orders+     # a model and everything downstream
dbt run   --select +fct_d2_revenue    # a model and everything upstream
dbt build --exclude path:models/day1  # everything except day 1
dbt test                              # schema + singular tests
dbt compile                           # inspect compiled SQL under target/
duckdb practice.duckdb                # ad-hoc SQL inspection

docker compose exec -w /workspace_ref dbt dbt build --select path:models/day2
                                      # same, in the reference-solution project
```

Node selection syntax (`path:`, `tag:`, `+` upstream/downstream, `--exclude`) is itself
interview-relevant; prefer scoped commands over bare `dbt build` even when the project
is small.

## Databricks companion environment (course only)

Used to follow dbt Fundamentals / later course demos against Databricks free edition
with a serverless SQL warehouse and Unity Catalog. **Not** used for practice problems.

Install with pip in a dedicated venv — not Homebrew. Homebrew's dbt formulas lag
upstream, split each adapter into its own formula, and give weaker version isolation;
pip + venv is the documented path and keeps `dbt-duckdb` and `dbt-databricks` from
colliding.

```bash
python3 -m venv ~/dbt-databricks-env
source ~/dbt-databricks-env/bin/activate
pip install dbt-databricks        # pulls a compatible dbt-core automatically
dbt --version                     # confirm the databricks plugin is listed
```

Project scaffold: `dbt init <project_name>` (interactive; writes the profile into
`~/.dbt/profiles.yml`), or hand-write:

```yaml
<project_name>:
  target: dev
  outputs:
    dev:
      type: databricks
      host: <workspace>.cloud.databricks.com   # no https:// prefix
      http_path: /sql/1.0/warehouses/<warehouse-id>
      token: <PAT>
      catalog: <unity_catalog_name>
      schema: <default_schema>
      threads: 4
```

`host` and `http_path` come from the SQL warehouse's **Connection details** tab.
Validate with `dbt debug` before running any model.

## VS Code's role

VS Code is an **editor only**. dbt models are executed from the terminal
(`dbt run` / `dbt build` / `dbt debug`) — there is no native "run this model" button,
and no extension is required to execute anything. Extensions are optional aids:

- Databricks extension — workspace sync, jobs, Databricks Connect; not a SQL warehouse
  query client and not needed for dbt.
- SQLTools (+ a DuckDB or Databricks driver) — browsing tables and ad-hoc queries,
  the GUI equivalent of the `duckdb practice.duckdb` CLI step.

If `dbt` is "not found", the cause is installation/PATH, never a missing extension.

## Conventions

- Seeds `raw_dN_*`; staging `stg_dN_*`; intermediate `int_dN_*`; marts
  `fct_dN_*` / `dim_dN_*` or business-named with the same prefix.
- Inspect expected-output mismatches with a manual query in the DuckDB CLI before
  concluding whose code is wrong.
- The `.duckdb` file is disposable: `rm practice.duckdb && dbt build` gives a clean
  rebuild whenever state is suspect. (No equivalent one-liner exists on Databricks —
  another reason the two environments stay separate.)
