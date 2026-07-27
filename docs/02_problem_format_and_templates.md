# Problem Format & Templates

## 1. Canonical problem format

Every problem is a single markdown file named `dbt_dayN_<topic_slug>.md` with these
sections, in order:

```
# dbt Daily Practice — Day N

**Topic:** <dbt feature(s) under practice>
**Difficulty:** Easy | Medium | Hard
**Prerequisite course:** <dbt Learn module, if any>

## Problem
Business scenario + requirements. Must specify:
- required models and layers (staging / intermediate / marts)
- required materializations
- for every mart: explicit grain, and per-metric definition
  (aggregation + filter stated unambiguously — EXCEPT when ambiguity is the trap)

## Input
Seed CSVs, given inline as fenced csv blocks, one per file under seeds/.

## Expected Output
Exact expected rows of the final model(s), as markdown tables.
State ordering; if unordered, comparison is order-insensitive.

## Verification
The schema.yml test suite that constitutes acceptance criteria.
`dbt build` green + expected-output match = pass.

## Deliverables
File list Neil must produce.

## Debrief questions
2-4 questions, answered in written English after Verify. At least one must be a
trade-off question ("why X over Y, and when would you reverse it").
```

Design rule: each problem embeds 2-3 deliberate traps; at least one must be exposed by
a failing test if handled naively (e.g., a relationships test failing when filtering is
applied to one model but not its child).

## 2. Solution submission format (Neil → chat)

When posting a solution for the record, use one fenced block per file, each preceded by
its path:

```
-- models/staging/stg_orders.sql
<sql>
```
```
# models/staging/schema.yml
<yaml>
```

Plus a one-paragraph English note on materialization choices and any assumption made
where the problem was ambiguous.

## 3. Standard generation prompt (for the incognito conversation)

Paste the following, then the Problem / Input / Expected Output / Verification sections
of the day's problem file — nothing else:

```
You are an experienced analytics engineer. Solve the following dbt practice problem
for a local dbt Core + DuckDB (dbt-duckdb adapter) environment.

Requirements:
- Provide complete file contents for every model and schema.yml, each in its own
  fenced code block preceded by its file path.
- Staging models materialized as views, marts as tables, unless the problem says
  otherwise; show where you configure this.
- Use ref()/source() correctly; never select from seeds directly in marts.
- SQL should be portable where reasonable; if you use a DuckDB-specific function,
  add a one-line comment noting the portable alternative.
- After the code, add a short "Design notes" section (max 5 bullets) explaining
  non-obvious choices.
- Do not include any explanation of how to install or run dbt.
```

## 4. Difficulty calibration

- **Easy:** single trap class, ≤3 models, tests given verbatim in the problem.
- **Medium:** 2-3 trap classes, may require writing an intermediate model, some tests
  specified only as intent ("guarantee referential integrity between X and Y") that
  Neil must translate into schema.yml.
- **Hard:** ambiguous requirements on purpose (Neil must state assumptions before
  solving), custom generic test or macro required, or incremental/snapshot semantics
  with late-arriving / reprocessed data.
