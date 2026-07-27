# Curriculum Backlog

Interleaved with dbt Learn courses: finish the listed course, then do its practice
block before starting the next course. Order within a block is flexible; blocks are not.
Prioritization principle (same as PySpark sprint planning): interview frequency ×
practical usage.

## Block 1 — after **dbt Fundamentals**

- Day 1: staging layer + ref() layering + schema tests (Easy) — file already written
- Day 2: sources vs seeds; source() + source freshness config; renaming/typing
  discipline in staging (Easy)
- Day 3: materialization trade-offs — view vs table vs ephemeral; config precedence
  (dbt_project.yml vs per-model config) (Easy-Medium)
- Day 4: test design — accepted_values / relationships / singular tests; translating a
  written data contract into a test suite (Medium)

## Block 2 — after **Incremental Models**

- Day 5: basic incremental model with is_incremental() + unique_key (Medium)
- Day 6: late-arriving data and the lookback window pattern; when incremental gives
  wrong answers and full-refresh semantics (Medium-Hard)

## Block 3 — after **Snapshots / SCD**

- Day 7: snapshot with timestamp strategy → SCD2 dimension; dbt_valid_from/to
  mechanics (Medium) — cross-reference ChargeGo SCD2 query patterns
- Day 8: check strategy vs timestamp strategy; hard deletes; building a current-view
  dim on top of a snapshot (Medium-Hard)

## Block 4 — after **Jinja, Macros & Packages**

- Day 9: Jinja loops to generate repetitive conditional-aggregation SQL (the dbt
  version of the PySpark pivot drills) (Medium)
- Day 10: writing a custom macro + using dbt_utils (surrogate_key, date_spine) (Medium)
- Day 11: custom generic test with configurable arguments (Medium-Hard)

## Block 5 — after **Advanced Testing / Deployment** (or standalone)

- Day 12: refactoring a legacy 200-line SQL script into layered dbt models (Hard;
  classic AE interview task)
- Day 13: environments & targets; dev vs prod schemas; what a CI run should execute
  (state/deferral discussed at concept level) (Medium)
- Day 14: docs, exposures, and semantic hygiene — description coverage as a deliverable
  (Easy; pairs with AI-era positioning: clean semantics for downstream AI consumers)

## Parked / on demand

- dbt Mesh (concept-level only; certification topic, low hands-on value locally)
- Python models in dbt-duckdb
- MetricFlow / semantic layer (revisit if targeted JDs mention it)

## Revision rule

After Block 3, schedule one **mixed-topic review day** (random earlier trap classes,
new data) before proceeding — spaced repetition beats forward-only progress.
