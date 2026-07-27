# Progress Log (living document — Neil updates after every day)

## Course progress

| dbt Learn course | Status | Completed on |
|---|---|---|
| dbt Fundamentals | completed | 2026-07-25 |
| Incremental Models | in progress | |
| Snapshots / SCD | not started | |
| Jinja, Macros & Packages | in progress | |
| Advanced Testing | not started | |

## Practice days

| Day | Topic | Difficulty | Date | Verdict scorecard | Result |
|---|---|---|---|---|---|
| 1 | staging + ref + tests | Easy | | | |

## Digest archive

(Append each day's Digest block here, newest at the bottom.)

## Cumulative blindspot log

Recurring error patterns across ALL practice tracks (carry-ins from PySpark and
dimensional modeling included, so cross-domain repeats are visible):

- [modeling] Editing schema correctly but leaving contradictory statements in earlier
  analysis sections → checklist sync step required
- [modeling] NULL-exclusion bugs silently dropping rows from rate calculations
- [general] Deferring a topic without extracting a one-sentence summary first
- [general] Missing ambiguous quantifiers in requirements as prompts for clarification
- [dbt] (populate as days complete)

## Parking lot (deferred topics, each with a one-sentence summary)

| Topic | One-sentence summary | Deferred on | Revisit when |
|---|---|---|---|
| dbt state / deferral | CI optimization that builds only changed models by comparing manifests | project setup | Block 5 Day 13 |
