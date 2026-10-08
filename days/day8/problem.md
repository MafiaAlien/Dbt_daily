# dbt Daily Practice — Day 8

**Topic:** snapshots, part two — `check` vs `timestamp` change detection, hard deletes,
and building a current-view dimension on top of a snapshot
**Difficulty:** Medium-Hard
**Prerequisite course:** Snapshots / SCD

## Problem

A 300-person logistics company keeps its employee roster in an HR application. Every
night the application exports a **full dump** of the roster: one row per employee who is
employed at that moment, and nothing else. The application keeps no history. It overwrites
records in place, and when someone is terminated, their record simply stops appearing
in the dump.

People Analytics needs three things from this feed:

- **A history** — for every employee, which department, title and salary band they held,
  and from when to when. Terminations must appear in that history as events you can count.
- **A current roster** — one row per employee employed today.
- **A department summary** — current headcount and terminations to date, per department.

Day 7's feed was a version log with a timestamp you could trust. This one is a nightly
picture with no trustworthy change timestamp, and rows that vanish. Most of the day is
deciding how a snapshot should *notice* things.

### The feeds

- `raw_d8_employee_dump` — the nightly roster dump, three nights of it, distinguished by
  `BATCH_ID`. **Each batch is complete**: every employee employed that night appears exactly
  once, and an employee who does not appear has been terminated as of that night. A
  terminated employee can be rehired, and then reappears under the **same**
  `EMPLOYEE_ID`.
- `raw_d8_departments` — department lookup. **Static: fully loaded from the start, not
  batched.** It does not participate in the batch simulation below.

Know what each column of the dump is before you configure anything:

| column | what it is |
|---|---|
| `EMPLOYEE_ID` | the business key |
| `FULL_NAME` | the employee's name |
| `DEPARTMENT_CODE` | the department the employee belongs to |
| `JOB_TITLE` | the employee's job title |
| `SALARY_BAND` | `B1`–`B5` |
| `RECORD_UPDATED_AT` | set by the HR application whenever a record is edited **through its UI** — promotions, name corrections, rehires. **Bulk changes run by IT scripts write straight to the table and do not touch it.** The May reorganisation in this data is one of those. |
| `LAST_LOGIN_AT` | written by the SSO system on every login. It changes most nights. It is not HR data. |
| `BATCH_ID` | the night of the dump; plumbing, not data |

HR has decided which changes count as history:

- **Tracked — every change is a new version:** `department_code`, `job_title`,
  `salary_band`.
- **Overwrite — never versioned, always shown as today's value:** `full_name` (a name
  change is a correction, not an event, and the history must not record it) and
  `last_login_at`.
- `record_updated_at` is bookkeeping. It is neither, and it decides nothing.

### Simulating three nightly snapshot runs

As on Day 7, a var stands in for the scheduler. The staging model over the dump ends with
exactly this clause. Copy it verbatim; it is not the exercise:

```sql
where batch_id = {{ var('d8_batch', 1) }}
```

Note the `=`. Day 7 used `<=`, because that feed was a version log. This one is a full
picture per night, so the relation the snapshot reads is *one night's dump*, nothing more.

Run 1 leaves the var at its default. Run 2 passes `--vars '{d8_batch: 2}'`, run 3
`--vars '{d8_batch: 3}'`. Exact commands are in `## Verification`. **All three runs are
graded**, and the snapshot is graded after each. The intermediate model and the marts are
graded after run 3.

The snapshot is still the one table here that cannot be rebuilt from source. Read
`### Starting over` before run 1.

### Layer 1 — staging (views)

`stg_d8_employees` — from seed `raw_d8_employee_dump`.
**Grain: one row per `employee_id` — 7 rows at `d8_batch=1`, 5 at `d8_batch=2`, 6 at
`d8_batch=3`.** Rename and cast only; no filtering beyond the `batch_id` clause above.

| column | type | source column |
|---|---|---|
| `employee_id` | varchar | `EMPLOYEE_ID` |
| `full_name` | varchar | `FULL_NAME` |
| `department_code` | varchar | `DEPARTMENT_CODE` |
| `job_title` | varchar | `JOB_TITLE` |
| `salary_band` | varchar | `SALARY_BAND` |
| `record_updated_at` | timestamp | `RECORD_UPDATED_AT` |
| `last_login_at` | timestamp | `LAST_LOGIN_AT` |

`stg_d8_departments` — from seed `raw_d8_departments`. **Grain: one row per
`department_code` — 5 rows, at every batch.**

| column | type | source column |
|---|---|---|
| `department_code` | varchar | `DEPARTMENT_CODE` |
| `department_name` | varchar | `DEPARTMENT_NAME` |

`batch_id` is used by the filter and is **not** published. Both models expose exactly the
columns listed, in that order, and **the final select of each lists them by name** — no
`select *` anywhere in this day's staging layer. Day 7's `select *` carried a helper column
into a snapshot and crashed the engine on every run.

### Layer 2 — the snapshot

`snap_d8_employees`, in `dbt_practice/snapshots/day8/`, defined in YAML (`snapshots:`).

- Its relation is `stg_d8_employees`, by `ref()`, **all seven columns**. HR's auditors want
  the full row as it stood when each version was recorded, overwrite columns included.
- `unique_key` is `employee_id`.
- **Change detection is yours**: strategy, and whatever that strategy needs. The column
  table above is the whole specification. Choose so that a new version is created **if and
  only if** a tracked column changed. A change only to an overwrite column, or only to
  `record_updated_at`, creates no version. A tracked change made by a bulk script still
  creates one.
- **A termination is a row.** When an employee disappears from the dump, the snapshot must
  record that as a row of its own: a separate, flagged version, not just a closed window.
  A rehire after a termination is a new version as well. dbt has a config for this; find
  it and say in `notes.md` what its other values would have done here.
- Leave `dbt_valid_to_current` and `snapshot_meta_column_names` at their defaults.

On top of the relation's seven columns the snapshot publishes the dbt-managed ones:
`dbt_scd_id`, `dbt_updated_at`, `dbt_valid_from`, `dbt_valid_to`, and the termination flag
`dbt_is_deleted`. **Only the snapshot itself and `int_d8_employee_history` read from the
snapshot table.** Marts never do.

### Layer 3 — intermediate (view, required)

`int_d8_employee_history` — from `snap_d8_employees`.

**Grain: one row per snapshot row**, so 16 rows after run 3. It is the one clean, typed
interface to the history that every downstream model reads.

| column | type | definition |
|---|---|---|
| `employee_id` | varchar | |
| `department_code` | varchar | the version's value |
| `job_title` | varchar | the version's value |
| `salary_band` | varchar | the version's value |
| `dbt_valid_from` | timestamp | unchanged |
| `dbt_valid_to` | timestamp | unchanged, `NULL` stays `NULL` |
| `is_deleted` | boolean | `true` if and only if this row is a termination record |
| `is_current` | boolean | `true` if and only if this row describes an employee **who is employed today**, in the version that applies today. At most one row per employee. Zero for someone not employed today. |

`full_name`, `last_login_at`, `record_updated_at`, `dbt_scd_id`, `dbt_updated_at` and the
raw `dbt_is_deleted` are **not** published.

### Layer 4 — marts (tables)

#### `dim_d8_employees_current`

**Grain: one row per employee employed today** — exactly the employees in the latest dump.

| column | type | definition |
|---|---|---|
| `employee_id` | varchar | grain |
| `full_name` | varchar | **today's value** (overwrite column) |
| `department_code` | varchar | from the current version |
| `job_title` | varchar | from the current version |
| `salary_band` | varchar | from the current version |
| `last_login_at` | timestamp | **today's value** (overwrite column) |
| `current_since` | timestamp | the `dbt_valid_from` of the current version |

#### `agg_d8_department_headcount`

**Grain: one row per department in `stg_d8_departments` — all five, always**, including any
department that has nobody in it.

| column | type | definition |
|---|---|---|
| `department_code` | varchar | grain |
| `department_name` | varchar | from `stg_d8_departments` |
| `current_headcount` | integer | number of rows of `dim_d8_employees_current` in this department; `0` if none |
| `terminations_to_date` | integer | number of termination records in the history whose `department_code` is this department, i.e. the department the employee was in **when** terminated. Every termination counts, including one later undone by a rehire. `0` if none |

## Input

`dbt_practice/seeds/day8/raw_d8_employee_dump.csv` — already loaded, do not edit.

```csv
EMPLOYEE_ID,FULL_NAME,DEPARTMENT_CODE,JOB_TITLE,SALARY_BAND,RECORD_UPDATED_AT,LAST_LOGIN_AT,BATCH_ID
E01,Ana Ruiz,ENG,Engineer II,B3,2026-03-10 09:00:00,2026-04-30 18:05:00,1
E02,Ben Okafor,ENG,Senior Engineer,B4,2026-02-01 10:00:00,2026-04-30 09:12:00,1
E03,Chloe Martin,OPS,Operations Analyst,B2,2026-01-15 08:30:00,2026-04-29 16:40:00,1
E04,Dev Patel,OPS,Operations Manager,B4,2025-11-20 11:00:00,2026-04-30 08:01:00,1
E05,Erin Walsh,FIN,Accountant,B3,2026-04-02 14:00:00,2026-04-28 12:30:00,1
E06,Farid Haddad,SALES,Account Executive,B3,2026-03-28 09:45:00,2026-04-30 17:55:00,1
E07,Grace Liu,FIN,Controller,B5,2025-12-05 13:00:00,2026-04-27 10:10:00,1
E01,Ana Ruiz,ENG,Engineer II,B3,2026-03-10 09:00:00,2026-05-01 17:20:00,2
E02,Ben Okafor,ENG,Senior Engineer,B4,2026-02-01 10:00:00,2026-05-01 08:58:00,2
E03,Chloe Martin,LOG,Operations Analyst,B2,2026-01-15 08:30:00,2026-05-01 15:02:00,2
E04,Dev Patel,LOG,Operations Manager,B4,2025-11-20 11:00:00,2026-05-01 07:45:00,2
E05,Erin Walsh,FIN,Senior Accountant,B4,2026-05-01 16:20:00,2026-05-01 16:25:00,2
E01,Ana Ruiz,ENG,Engineer III,B4,2026-05-02 10:30:00,2026-05-02 18:10:00,3
E02,Benedict Okafor,ENG,Senior Engineer,B4,2026-05-02 11:00:00,2026-05-02 09:05:00,3
E03,Chloe Martin,LOG,Operations Analyst,B2,2026-01-15 08:30:00,2026-05-02 14:48:00,3
E05,Erin Walsh,FIN,Senior Accountant,B4,2026-05-01 16:20:00,2026-05-02 11:37:00,3
E07,Grace Liu,FIN,Controller,B5,2026-05-02 15:00:00,2026-05-02 15:20:00,3
E08,Hana Sato,SALES,Account Executive,B3,2026-05-02 09:00:00,2026-05-02 16:00:00,3
```

`dbt_practice/seeds/day8/raw_d8_departments.csv` — already loaded, do not edit.

```csv
DEPARTMENT_CODE,DEPARTMENT_NAME
ENG,Engineering
FIN,Finance
LOG,Logistics
OPS,Operations
SALES,Sales
```

## Expected Output

### Reading the timestamps

Under the configuration this day requires, `dbt_valid_from` and `dbt_valid_to` are not
values in the input. They are produced when you run it, so no fixed timestamp can be
printed here. The tables therefore name each one by the run that wrote it:

- **R1, R2, R3** — the moment run 1, 2, 3's snapshot executed.
- **open** — `dbt_valid_to` is `NULL`.

The capture commands in `## Verification` do this mapping for you: they rank the distinct
`dbt_valid_from` values in the snapshot and label them `R1`, `R2`, `R3`. If your snapshot
holds any `dbt_valid_from` that is not one of the three run times, it holds more than
three distinct values, the labels run past `R3`, and your table will not match. That is
intended.

`full_name`, `last_login_at` and `record_updated_at` are present in the snapshot and are
not shown in its tables below.

### `snap_d8_employees` after each run

Ordered by `employee_id`, then `dbt_valid_from`. **All three are graded.**

#### After run 1 — `d8_batch` at its default (7 rows)

| employee_id | department_code | job_title | salary_band | dbt_is_deleted | window |
|---|---|---|---|---|---|
| E01 | ENG | Engineer II | B3 | False | R1 → open |
| E02 | ENG | Senior Engineer | B4 | False | R1 → open |
| E03 | OPS | Operations Analyst | B2 | False | R1 → open |
| E04 | OPS | Operations Manager | B4 | False | R1 → open |
| E05 | FIN | Accountant | B3 | False | R1 → open |
| E06 | SALES | Account Executive | B3 | False | R1 → open |
| E07 | FIN | Controller | B5 | False | R1 → open |

#### After run 2 — `--vars '{d8_batch: 2}'` (12 rows)

| employee_id | department_code | job_title | salary_band | dbt_is_deleted | window |
|---|---|---|---|---|---|
| E01 | ENG | Engineer II | B3 | False | R1 → open |
| E02 | ENG | Senior Engineer | B4 | False | R1 → open |
| E03 | OPS | Operations Analyst | B2 | False | R1 → R2 |
| E03 | LOG | Operations Analyst | B2 | False | R2 → open |
| E04 | OPS | Operations Manager | B4 | False | R1 → R2 |
| E04 | LOG | Operations Manager | B4 | False | R2 → open |
| E05 | FIN | Accountant | B3 | False | R1 → R2 |
| E05 | FIN | Senior Accountant | B4 | False | R2 → open |
| E06 | SALES | Account Executive | B3 | False | R1 → R2 |
| E06 | SALES | Account Executive | B3 | True | R2 → open |
| E07 | FIN | Controller | B5 | False | R1 → R2 |
| E07 | FIN | Controller | B5 | True | R2 → open |

#### After run 3 — `--vars '{d8_batch: 3}'` (16 rows)

| employee_id | department_code | job_title | salary_band | dbt_is_deleted | window |
|---|---|---|---|---|---|
| E01 | ENG | Engineer II | B3 | False | R1 → R3 |
| E01 | ENG | Engineer III | B4 | False | R3 → open |
| E02 | ENG | Senior Engineer | B4 | False | R1 → open |
| E03 | OPS | Operations Analyst | B2 | False | R1 → R2 |
| E03 | LOG | Operations Analyst | B2 | False | R2 → open |
| E04 | OPS | Operations Manager | B4 | False | R1 → R2 |
| E04 | LOG | Operations Manager | B4 | False | R2 → R3 |
| E04 | LOG | Operations Manager | B4 | True | R3 → open |
| E05 | FIN | Accountant | B3 | False | R1 → R2 |
| E05 | FIN | Senior Accountant | B4 | False | R2 → open |
| E06 | SALES | Account Executive | B3 | False | R1 → R2 |
| E06 | SALES | Account Executive | B3 | True | R2 → open |
| E07 | FIN | Controller | B5 | False | R1 → R2 |
| E07 | FIN | Controller | B5 | True | R2 → R3 |
| E07 | FIN | Controller | B5 | False | R3 → open |
| E08 | SALES | Account Executive | B3 | False | R3 → open |

**Sixteen rows for eighteen input rows across three dumps** — and the arithmetic does not
work the way it did on Day 7. Before you write a line of config, account for each run's new
rows in words: which input change caused each, and which input changes in the same batch
caused **none**. Every batch-to-batch difference in `## Input` belongs on exactly one of
those two lists.

### `int_d8_employee_history` after run 3

16 rows, one per snapshot row above. `is_deleted` is `true` on exactly the three `True`
rows. `is_current` is `true` on exactly six rows: the six that `dim_d8_employees_current`
is built from.

### `dim_d8_employees_current` after run 3 (6 rows)

Ordered by `employee_id`.

| employee_id | full_name | department_code | job_title | salary_band | last_login_at | current_since |
|---|---|---|---|---|---|---|
| E01 | Ana Ruiz | ENG | Engineer III | B4 | 2026-05-02 18:10:00 | R3 |
| E02 | Benedict Okafor | ENG | Senior Engineer | B4 | 2026-05-02 09:05:00 | R1 |
| E03 | Chloe Martin | LOG | Operations Analyst | B2 | 2026-05-02 14:48:00 | R2 |
| E05 | Erin Walsh | FIN | Senior Accountant | B4 | 2026-05-02 11:37:00 | R2 |
| E07 | Grace Liu | FIN | Controller | B5 | 2026-05-02 15:20:00 | R3 |
| E08 | Hana Sato | SALES | Account Executive | B3 | 2026-05-02 16:00:00 | R3 |

### `agg_d8_department_headcount` after run 3 (5 rows)

Ordered by `department_code`.

| department_code | department_name | current_headcount | terminations_to_date |
|---|---|---|---|
| ENG | Engineering | 2 | 0 |
| FIN | Finance | 2 | 1 |
| LOG | Logistics | 1 | 1 |
| OPS | Operations | 0 | 0 |
| SALES | Sales | 1 | 1 |

`sum(current_headcount)` is **6**, the row count of the dim. `sum(terminations_to_date)`
is **3**, the number of `True` rows in the snapshot.

**Read the dim against the run-3 snapshot before you write the dim — row by row, column by
column.** Not every open snapshot row becomes a dim row, and not every dim value is copied
from an open snapshot row. Each mismatch is a different mistake if you get it wrong, and
only one of them turns a test red.

## Verification

### Tests you must write

The generic tests are named; the singular ones are stated as intent and you translate
them.

**No packages.** Anything the four built-in generic tests cannot express is a **singular
test** in `dbt_practice/tests/day8/`, one file per assertion, named after what it asserts.

**V1 — `stg_d8_employees`, generic.** `unique` and `not_null` on `employee_id`.
`not_null` on `full_name`, `department_code`, `job_title`, `salary_band`,
`record_updated_at`. `accepted_values` on `salary_band`: `B1`, `B2`, `B3`, `B4`, `B5`.
`relationships` from `department_code` to `stg_d8_departments.department_code`.
Say in one sentence why `unique` on `employee_id` is right here when Day 7 forbade it on
`stg_d7_account_versions`.

**V2 — `stg_d8_departments`, generic.** `unique` and `not_null` on `department_code`.
`not_null` on `department_name`.

**V3 — the snapshot, generic, in its YAML.** `not_null` on `employee_id`,
`department_code`, `job_title`, `salary_band`, `dbt_valid_from`, `dbt_is_deleted`.
`accepted_values` on `dbt_is_deleted`: `True`, `False`. Find out what data type that
column actually is before you write the values.

**V4 — the snapshot, intent.** Every `employee_id` in the snapshot has **exactly one** row
with `dbt_valid_to is null`. That includes employees who are no longer employed. Say in
`notes.md` which row that is for E06.

**V5 — the snapshot, intent.** No employee has two versions whose windows overlap, and no
window is empty. A window is `[dbt_valid_from, dbt_valid_to)`, with `NULL` meaning "open,
extends forever". This is Day 7's V6. Day 7's version never checked an empty window, and
never compared windows within one key. Write it so it would.

**V6 — the snapshot, intent: change detection against the dump. Both directions.** Compare
the snapshot's open, non-termination rows against `stg_d8_employees` (the latest dump):

> Every employee in the dump has exactly one open, non-termination row in the snapshot,
> and that row agrees with the dump on all three tracked columns. Every open,
> non-termination row in the snapshot belongs to an employee who is in the dump.

This is the test that proves the snapshot *noticed* what it was supposed to notice, in
both directions: a change it missed, and a termination it missed.

**V7 — the snapshot, intent: no redundant versions.** Take any two versions of one employee
where the first's `dbt_valid_to` equals the second's `dbt_valid_from`, and neither is a
termination record. They must differ in at least one tracked column. A version that
repeats its predecessor on every tracked column is a version that should not exist. This
is the test that proves the snapshot noticed *only* what it was supposed to.

**V8 — `int_d8_employee_history`, generic.** `not_null` on `employee_id`, `dbt_valid_from`,
`is_deleted`, `is_current`.

**V9 — `dim_d8_employees_current`, generic.** `unique` and `not_null` on `employee_id`.
`not_null` on `full_name`, `department_code`, `job_title`, `salary_band`, `current_since`.
`relationships` from `department_code` to `stg_d8_departments.department_code`.

**V10 — dim, intent: the reconciliation. Both directions.** In one singular test:

> Every `employee_id` in `stg_d8_employees` appears in the dim exactly once, and the dim
> contains no `employee_id` that is not in `stg_d8_employees`.

**Both directions, and this is the third day in a row this sentence has been printed.**
Day 6's V7 was `stg left join mart … where x <> y` and could not fire on a missing mart
row, because `x <> NULL` is `NULL`. Day 7's V9 had no staging→mart branch at all, and
measured on a broken mart it returned 0 rows. Shape to reach for: `full outer join` on the
key, and one `case` that names each failure direction.

**V11 — `agg_d8_department_headcount`, generic.** `unique` and `not_null` on
`department_code`. `not_null` on `department_name`, `current_headcount`,
`terminations_to_date`.

**V12 — agg, intent: totals tie out.** `sum(current_headcount)` equals the row count of
`dim_d8_employees_current`, and `sum(terminations_to_date)` equals the number of
termination records in the snapshot.

V4–V7, V10 and V12 must be part of `dbt build`, so they run on **every** run.

### Count your tests before you trust them

Count the assertions V1–V12 ask for and write the number into `notes.md` **before run 1**.
Then run:

```bash
docker compose exec dbt dbt ls --resource-type test --select path:models/day8 path:snapshots/day8 path:tests/day8 --quiet
```

and compare the two. If they differ, find out why before you go further. Day 6 lost eight
tests to a misspelled patch name, and Day 7 lost six to the same thing plus one to a `ref()`
of a model that does not exist. Both were parse-time **warnings**, and both builds still
said `WARN=0`.

### Starting over

A snapshot accumulates. To restart the three-run protocol (wrong order, a run repeated, a
config you want to change after run 1), **drop the snapshot table first**:

```bash
docker compose exec dbt python3 -c "import duckdb; duckdb.connect('/workspace/practice.duckdb').execute('drop table if exists main.snap_d8_employees')"
```

Then start again at run 1. Nothing else in the project needs resetting. Changing the
snapshot's change-detection config **without** dropping it is not a restart: the old
history stays, and the new config applies only from the next run onward.

### One warning that is not yours

Until your first model exists under each of `day8/staging/`, `day8/intermediate/` and
`day8/marts/`, every dbt command prints a `Configuration paths exist in your
dbt_project.yml file which do not apply to any resources` warning naming the empty ones.
That is the `day8:` block waiting for its models. It does not count in `WARN=`, and the
`day8:` block is not yours to edit.

### The three runs

```bash
# Run 1 — first nightly dump.
docker compose exec dbt dbt build --select path:models/day8 path:snapshots/day8 path:tests/day8
```

```bash
# capture the snapshot (after every run)
docker compose exec dbt dbt show --inline "with runs as (select ts, 'R' || row_number() over (order by ts) as run from (select distinct dbt_valid_from as ts from {{ ref('snap_d8_employees') }})) select s.employee_id, s.department_code, s.job_title, s.salary_band, s.dbt_is_deleted, f.run || ' -> ' || coalesce(t.run, 'open') as window from {{ ref('snap_d8_employees') }} s join runs f on s.dbt_valid_from = f.ts left join runs t on s.dbt_valid_to = t.ts order by s.employee_id, s.dbt_valid_from" --limit 30
```

```bash
# Run 2 — second nightly dump.
docker compose exec dbt dbt build --select path:models/day8 path:snapshots/day8 path:tests/day8 --vars '{d8_batch: 2}'
```

```bash
# Run 3 — third nightly dump.
docker compose exec dbt dbt build --select path:models/day8 path:snapshots/day8 path:tests/day8 --vars '{d8_batch: 3}'
```

```bash
# capture dim_d8_employees_current (after run 3). dbt show prints at most six columns,
# so title and band are joined here; the table itself keeps them separate.
docker compose exec dbt dbt show --inline "with runs as (select ts, 'R' || row_number() over (order by ts) as run from (select distinct dbt_valid_from as ts from {{ ref('snap_d8_employees') }})) select d.employee_id, d.full_name, d.department_code, d.job_title || ' / ' || d.salary_band as title_band, d.last_login_at, r.run as current_since from {{ ref('dim_d8_employees_current') }} d left join runs r on d.current_since = r.ts order by 1" --limit 30
```

```bash
# capture agg_d8_department_headcount (after run 3)
docker compose exec dbt dbt show --inline "select * from {{ ref('agg_d8_department_headcount') }} order by 1" --limit 30
```

```bash
# capture column types of both marts (after run 3)
docker compose exec dbt dbt show --inline "select table_name, column_name, data_type from information_schema.columns where table_name in ('dim_d8_employees_current', 'agg_d8_department_headcount') order by table_name, ordinal_position" --limit 30
```

Do **not** pass `--full-refresh` anywhere in this day.

### Pass condition

All six, or it is not a pass:

1. All three runs green: `ERROR=0`, `WARN=0`, `SKIP=0`, and the snapshot actually ran on
   each (`OK snapshotted`).
2. The test count from `dbt ls` equals the number of assertions V1–V12 ask for.
3. The snapshot matches the 7-row, 12-row and 16-row tables cell for cell, `window`
   column included.
4. `dim_d8_employees_current` matches its 6-row table cell for cell, including column types.
5. `agg_d8_department_headcount` matches its 5-row table cell for cell, including
   `integer` for both counts.
6. The two totals are exactly 6 and 3.

Green tests are necessary and not sufficient. At least one trap this day passes all twelve
verification items and is only visible by comparing cells.

## Deliverables

```
dbt_practice/models/day8/staging/stg_d8_employees.sql
dbt_practice/models/day8/staging/stg_d8_departments.sql
dbt_practice/models/day8/staging/schema.yml
dbt_practice/snapshots/day8/snap_d8_employees.yml
dbt_practice/models/day8/intermediate/int_d8_employee_history.sql
dbt_practice/models/day8/intermediate/schema.yml
dbt_practice/models/day8/marts/dim_d8_employees_current.sql
dbt_practice/models/day8/marts/agg_d8_department_headcount.sql
dbt_practice/models/day8/marts/schema.yml
dbt_practice/tests/day8/          (one .sql per intent assertion — V4, V5, V6, V7, V10, V12)
```

**Commit your models before `/review` runs.**

```bash
git add dbt_practice/models/day8 dbt_practice/snapshots/day8 dbt_practice/tests/day8 && git commit -m "Day 8 as submitted"
```

Day 7 was the first day this ran before review, and it is why Day 7's grade is not
provisional. The edits still happened afterwards, during phase 2. This day's target is
stricter: **no edits between the verdict commit and the end of `/review`.**

**Submit only a solution you have seen build.** Day 7's solution failed on every run, with
a DuckDB INTERNAL Error, and was submitted anyway. An engine error is an environment
problem, the one kind stage 1 lets you ask for help with. If your `## Run log` has no green
`Done.` line to paste, raise that. Do not submit around it.

Plus, in `days/day8/notes.md`:

- `## Column plan`: **a graded deliverable, and the first thing you write, before any
  config or SQL.** Three parts:
  1. For each of the seven `stg_d8_employees` columns: *tracked*, *overwrite* or
     *neither*. Then the snapshot config line(s) that make that classification true.
  2. For each of the seven `dim_d8_employees_current` columns: which relation it is read
     from, and why that relation and not another.
  3. The condition, written as a SQL predicate over snapshot columns, that makes a snapshot
     row "an employee employed today, in today's version". Then name the snapshot rows after
     run 3 that have `dbt_valid_to is null` and do **not** satisfy it.

  On Day 7, the one line of the plan that was written left out the `NULL` case, and that
  omission was the day's one trap hit in code. Part 3 here is that same kind of line.

- `## Snapshot config decisions`: the strategy, every config key you set, and where. What
  `dbt_valid_from` is set to under your choice, and why that is the right clock for this
  feed. What the other two values of the termination config would have produced for E06
  and E07.

- `## Test count`: the number of assertions V1–V12 ask for, the number `dbt ls` reported,
  and what the difference was if they ever differed.

- `## Assumptions`: anything you had to decide.

- `## Run log`: the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from all three builds, plus
  every captured table, **pasted, not summarized.**

- `## Debrief answers`: the four questions below, in written English.

`notes.md` has been blank, near-blank or stale for six consecutive days. On Days 6 and 7
the blank line was the defect that survived. The `## Column plan` above is built the same
way: parts 1 and 3 are the two decisions that this day's traps are made of.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **Trade-off: `check` versus `timestamp`, on this feed.** Name the strategy you chose and
   the exact config. Then, using the rows in `## Input`, for each alternative below name
   every run-3 snapshot row that would differ from `## Expected Output`, and which of V4–V7
   fires on which employee:
   (a) `strategy: timestamp`, `updated_at: record_updated_at`;
   (b) `strategy: check`, `check_cols: all`;
   (c) your `check` config with `updated_at: record_updated_at` added, "to get business
   time back into `dbt_valid_from`". Look at E03 and E07 in particular.
   Finally: what does your choice cost, and on what kind of feed would you reverse it?

2. **Hard deletes.** Give the three values of the termination config and what each
   produces for E06 (terminated in batch 2, never back) and E07 (terminated in batch 2,
   rehired in batch 3). Then: on Day 7, `dbt_valid_to is null` meant "current". Say
   precisely why it does not here, and what it does mean. Finally: the termination record's
   `dbt_valid_from` is the run time *whichever* strategy you choose. Say what that does to a
   timestamp-strategy snapshot's windows the night someone is rehired, and which of your
   tests would catch it.

3. **Trade-off: overwrite columns inside a versioned dimension.** List every cell of
   `dim_d8_employees_current` that would be wrong if `full_name` and `last_login_at` were
   read from the snapshot's current row. Say what value each would show and why. Then argue
   both sides: keeping overwrite columns in the snapshot at all (the auditors asked for
   it) versus excluding them from its relation. Say when you would promote `full_name` to
   a tracked column instead.

4. **Trade-off: the feed shape is part of the snapshot's contract.** Termination detection
   here rests on one sentence of `### The feeds`: each batch is complete. (a) IT switches
   the export to a *delta*, only the rows that changed that night, and nobody touches your
   snapshot config. Name every employee your snapshot terminates on the first delta night,
   using batch 2's changes as that delta. (b) Someone "fixes" the staging filter back to
   Day 7's `batch_id <= {{ var('d8_batch', 1) }}`. Say what breaks and how loudly. (c) Give
   the alternative design, where the source carries an `is_active` flag instead of dropping
   rows. Say what it changes in the snapshot config and the dim, and when you would ask the
   source team for it rather than rely on deletion detection.
