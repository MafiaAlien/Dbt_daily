The approach: a `check` snapshot on the three tracked columns, `hard_deletes: new_record` so that terminations become rows, and a dim that takes version columns from the history and overwrite columns from today's dump.

`dbt_practice/models/day8/staging/stg_d8_employees.sql`
```sql
{{ config(materialized='view') }}

with source as (

    select
        EMPLOYEE_ID,
        FULL_NAME,
        DEPARTMENT_CODE,
        JOB_TITLE,
        SALARY_BAND,
        RECORD_UPDATED_AT,
        LAST_LOGIN_AT,
        BATCH_ID
    from {{ ref('raw_d8_employee_dump') }}

),

renamed as (

    select
        cast(EMPLOYEE_ID       as varchar)   as employee_id,
        cast(FULL_NAME         as varchar)   as full_name,
        cast(DEPARTMENT_CODE   as varchar)   as department_code,
        cast(JOB_TITLE         as varchar)   as job_title,
        cast(SALARY_BAND       as varchar)   as salary_band,
        cast(RECORD_UPDATED_AT as timestamp) as record_updated_at,
        cast(LAST_LOGIN_AT     as timestamp) as last_login_at,
        cast(BATCH_ID          as integer)   as batch_id
    from source

)

select
    employee_id,
    full_name,
    department_code,
    job_title,
    salary_band,
    record_updated_at,
    last_login_at
from renamed
where batch_id = {{ var('d8_batch', 1) }}
```

`dbt_practice/models/day8/staging/stg_d8_departments.sql`
```sql
{{ config(materialized='view') }}

with source as (

    select
        DEPARTMENT_CODE,
        DEPARTMENT_NAME
    from {{ ref('raw_d8_departments') }}

),

renamed as (

    select
        cast(DEPARTMENT_CODE as varchar) as department_code,
        cast(DEPARTMENT_NAME as varchar) as department_name
    from source

)

select
    department_code,
    department_name
from renamed
```

`dbt_practice/models/day8/staging/schema.yml`
```yaml
version: 2

models:
  - name: stg_d8_employees
    description: "One night's full roster dump (batch selected by var d8_batch). One row per employee employed that night."
    columns:
      - name: employee_id
        data_tests:
          - unique
          - not_null
      - name: full_name
        data_tests:
          - not_null
      - name: department_code
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d8_departments')
              field: department_code
      - name: job_title
        data_tests:
          - not_null
      - name: salary_band
        data_tests:
          - not_null
          - accepted_values:
              values: ['B1', 'B2', 'B3', 'B4', 'B5']
      - name: record_updated_at
        data_tests:
          - not_null
      - name: last_login_at

  - name: stg_d8_departments
    description: "Static department lookup. Not batched."
    columns:
      - name: department_code
        data_tests:
          - unique
          - not_null
      - name: department_name
        data_tests:
          - not_null
```

`dbt_practice/snapshots/day8/snap_d8_employees.yml`
```yaml
version: 2

snapshots:
  - name: snap_d8_employees
    description: "SCD2 history of the nightly roster dump. Versions on tracked columns only; terminations are rows."
    relation: ref('stg_d8_employees')
    config:
      unique_key: employee_id
      strategy: check
      check_cols: ['department_code', 'job_title', 'salary_band']
      hard_deletes: new_record
    columns:
      - name: employee_id
        data_tests:
          - not_null
      - name: department_code
        data_tests:
          - not_null
      - name: job_title
        data_tests:
          - not_null
      - name: salary_band
        data_tests:
          - not_null
      - name: dbt_valid_from
        data_tests:
          - not_null
      - name: dbt_is_deleted
        description: "Written by dbt as the varchar literals 'True' / 'False', not a boolean."
        data_tests:
          - not_null
          - accepted_values:
              values: ['True', 'False']
```

`dbt_practice/models/day8/intermediate/int_d8_employee_history.sql`
```sql
{{ config(materialized='view') }}

with snapshot_rows as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        dbt_valid_from,
        dbt_valid_to,
        dbt_is_deleted
    from {{ ref('snap_d8_employees') }}

)

select
    cast(employee_id     as varchar)   as employee_id,
    cast(department_code as varchar)   as department_code,
    cast(job_title       as varchar)   as job_title,
    cast(salary_band     as varchar)   as salary_band,
    cast(dbt_valid_from  as timestamp) as dbt_valid_from,
    cast(dbt_valid_to    as timestamp) as dbt_valid_to,
    -- dbt writes the flag as the strings 'True' / 'False'
    case when dbt_is_deleted = 'True' then true else false end as is_deleted,
    -- open window (dbt_valid_to_current at default => NULL) and not a termination record
    case
        when dbt_valid_to is null and dbt_is_deleted <> 'True' then true
        else false
    end as is_current
from snapshot_rows
```

`dbt_practice/models/day8/intermediate/schema.yml`
```yaml
version: 2

models:
  - name: int_d8_employee_history
    description: "Typed interface to snap_d8_employees. One row per snapshot row."
    columns:
      - name: employee_id
        data_tests:
          - not_null
      - name: department_code
      - name: job_title
      - name: salary_band
      - name: dbt_valid_from
        data_tests:
          - not_null
      - name: dbt_valid_to
      - name: is_deleted
        data_tests:
          - not_null
      - name: is_current
        data_tests:
          - not_null
```

`dbt_practice/models/day8/marts/dim_d8_employees_current.sql`
```sql
{{ config(materialized='table') }}

with current_versions as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        dbt_valid_from
    from {{ ref('int_d8_employee_history') }}
    where is_current = true

),

todays_dump as (

    select
        employee_id,
        full_name,
        last_login_at
    from {{ ref('stg_d8_employees') }}

)

select
    cast(v.employee_id     as varchar)   as employee_id,
    cast(d.full_name       as varchar)   as full_name,       -- overwrite column: today's value
    cast(v.department_code as varchar)   as department_code,
    cast(v.job_title       as varchar)   as job_title,
    cast(v.salary_band     as varchar)   as salary_band,
    cast(d.last_login_at   as timestamp) as last_login_at,   -- overwrite column: today's value
    cast(v.dbt_valid_from  as timestamp) as current_since
from current_versions as v
left join todays_dump as d
    on d.employee_id = v.employee_id
```

`dbt_practice/models/day8/marts/agg_d8_department_headcount.sql`
```sql
{{ config(materialized='table') }}

with departments as (

    select
        department_code,
        department_name
    from {{ ref('stg_d8_departments') }}

),

headcount as (

    select
        department_code,
        count(*) as n
    from {{ ref('dim_d8_employees_current') }}
    group by department_code

),

terminations as (

    -- department on the termination record = department at the moment of termination
    select
        department_code,
        count(*) as n
    from {{ ref('int_d8_employee_history') }}
    where is_deleted = true
    group by department_code

)

select
    dep.department_code,
    dep.department_name,
    cast(coalesce(h.n, 0) as integer) as current_headcount,
    cast(coalesce(t.n, 0) as integer) as terminations_to_date
from departments as dep
left join headcount as h
    on h.department_code = dep.department_code
left join terminations as t
    on t.department_code = dep.department_code
```

`dbt_practice/models/day8/marts/schema.yml`
```yaml
version: 2

models:
  - name: dim_d8_employees_current
    description: "One row per employee in the latest dump. Version columns from history, overwrite columns from today's dump."
    columns:
      - name: employee_id
        data_tests:
          - unique
          - not_null
      - name: full_name
        data_tests:
          - not_null
      - name: department_code
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d8_departments')
              field: department_code
      - name: job_title
        data_tests:
          - not_null
      - name: salary_band
        data_tests:
          - not_null
      - name: last_login_at
      - name: current_since
        data_tests:
          - not_null

  - name: agg_d8_department_headcount
    description: "One row per department, all five always."
    columns:
      - name: department_code
        data_tests:
          - unique
          - not_null
      - name: department_name
        data_tests:
          - not_null
      - name: current_headcount
        data_tests:
          - not_null
      - name: terminations_to_date
        data_tests:
          - not_null
```

`dbt_practice/tests/day8/assert_snap_d8_exactly_one_open_row_per_employee.sql`
```sql
-- V4: every employee_id has exactly one row with dbt_valid_to is null (terminated ones included)
select
    employee_id,
    count(case when dbt_valid_to is null then 1 end) as open_rows
from {{ ref('snap_d8_employees') }}
group by employee_id
having count(case when dbt_valid_to is null then 1 end) <> 1
```

`dbt_practice/tests/day8/assert_snap_d8_windows_non_empty_and_non_overlapping.sql`
```sql
-- V5: windows are [dbt_valid_from, dbt_valid_to), NULL = open-ended.
-- No window is empty, and no two versions of the same employee overlap.
with versions as (

    select
        employee_id,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (
            partition by employee_id
            order by dbt_valid_from, dbt_valid_to nulls last
        ) as version_seq
    from {{ ref('snap_d8_employees') }}

),

empty_windows as (

    select
        employee_id,
        'empty window' as failure,
        dbt_valid_from as from_a,
        dbt_valid_to   as to_a,
        cast(null as timestamp) as from_b,
        cast(null as timestamp) as to_b
    from versions
    where dbt_valid_to is not null
      and dbt_valid_to <= dbt_valid_from

),

overlaps as (

    select
        a.employee_id,
        'overlapping windows' as failure,
        a.dbt_valid_from as from_a,
        a.dbt_valid_to   as to_a,
        b.dbt_valid_from as from_b,
        b.dbt_valid_to   as to_b
    from versions as a
    join versions as b
        on  a.employee_id = b.employee_id
        and a.version_seq < b.version_seq
    where (b.dbt_valid_to is null or a.dbt_valid_from < b.dbt_valid_to)
      and (a.dbt_valid_to is null or b.dbt_valid_from < a.dbt_valid_to)

)

select * from empty_windows
union all
select * from overlaps
```

`dbt_practice/tests/day8/assert_snap_d8_open_versions_match_latest_dump.sql`
```sql
-- V6: both directions between the latest dump and the snapshot's open, non-termination rows.
with dump as (

    select employee_id, department_code, job_title, salary_band
    from {{ ref('stg_d8_employees') }}

),

open_versions as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        count(*) over (partition by employee_id) as open_versions_for_key
    from {{ ref('snap_d8_employees') }}
    where dbt_valid_to is null
      and dbt_is_deleted <> 'True'

),

compared as (

    select
        coalesce(d.employee_id, o.employee_id) as employee_id,
        case
            when o.employee_id is null
                then 'in dump, no open version in snapshot (missed insert/rehire)'
            when d.employee_id is null
                then 'open version for employee not in dump (missed termination)'
            when o.open_versions_for_key > 1
                then 'more than one open non-termination version'
            when d.department_code is distinct from o.department_code
              or d.job_title       is distinct from o.job_title
              or d.salary_band     is distinct from o.salary_band
                then 'tracked column differs from dump (missed change)'
        end as failure
    from dump as d
    full outer join open_versions as o
        on d.employee_id = o.employee_id

)

select employee_id, failure
from compared
where failure is not null
```

`dbt_practice/tests/day8/assert_snap_d8_no_redundant_versions.sql`
```sql
-- V7: consecutive non-termination versions of one employee must differ in a tracked column.
with versions as (

    select employee_id, department_code, job_title, salary_band,
           dbt_valid_from, dbt_valid_to, dbt_is_deleted
    from {{ ref('snap_d8_employees') }}

)

select
    a.employee_id,
    a.dbt_valid_from as earlier_from,
    b.dbt_valid_from as later_from
from versions as a
join versions as b
    on  a.employee_id  = b.employee_id
    and a.dbt_valid_to = b.dbt_valid_from
where a.dbt_is_deleted <> 'True'
  and b.dbt_is_deleted <> 'True'
  and a.department_code is not distinct from b.department_code
  and a.job_title       is not distinct from b.job_title
  and a.salary_band     is not distinct from b.salary_band
```

`dbt_practice/tests/day8/assert_dim_d8_reconciles_with_latest_dump.sql`
```sql
-- V10: every stg employee appears in the dim exactly once; the dim has nobody not in stg.
with stg as (

    select employee_id
    from {{ ref('stg_d8_employees') }}

),

dim as (

    select employee_id, count(*) as dim_rows
    from {{ ref('dim_d8_employees_current') }}
    group by employee_id

),

compared as (

    select
        coalesce(s.employee_id, d.employee_id) as employee_id,
        case
            when d.employee_id is null then 'in stg_d8_employees, missing from dim'
            when s.employee_id is null then 'in dim, not in stg_d8_employees'
            when d.dim_rows > 1        then 'duplicated in dim'
        end as failure
    from stg as s
    full outer join dim as d
        on s.employee_id = d.employee_id

)

select employee_id, failure
from compared
where failure is not null
```

`dbt_practice/tests/day8/assert_agg_d8_totals_tie_out.sql`
```sql
-- V12: sum(current_headcount) = rows in dim; sum(terminations_to_date) = termination records in snapshot.
with agg_totals as (

    select
        coalesce(sum(current_headcount), 0)    as total_headcount,
        coalesce(sum(terminations_to_date), 0) as total_terminations
    from {{ ref('agg_d8_department_headcount') }}

),

dim_total as (

    select count(*) as dim_rows
    from {{ ref('dim_d8_employees_current') }}

),

snap_total as (

    select count(*) as termination_records
    from {{ ref('snap_d8_employees') }}
    where dbt_is_deleted = 'True'

)

select
    a.total_headcount,
    d.dim_rows,
    a.total_terminations,
    s.termination_records
from agg_totals as a
cross join dim_total as d
cross join snap_total as s
where a.total_headcount    <> d.dim_rows
   or a.total_terminations <> s.termination_records
```

`dbt_practice/notes.md`
```markdown
## Day 8

### Test count (written before run 1): 42

| item | assertions |
|---|---|
| V1 stg_d8_employees | 9 (unique + 6 not_null + accepted_values + relationships) |
| V2 stg_d8_departments | 3 |
| V3 snapshot generic | 7 (6 not_null + accepted_values) |
| V4, V5, V6, V7 | 4 singular |
| V8 int_d8_employee_history | 4 |
| V9 dim | 8 (unique + 6 not_null + relationships) |
| V10 | 1 singular |
| V11 agg | 5 |
| V12 | 1 singular |
| **total** | **42** |

### V1: why `unique` on employee_id is right here
Each batch is a complete one-row-per-employee picture and the staging view selects exactly one
batch (`=`), whereas Day 7's `<=` over a version log deliberately kept several versions per account.

### Accounting for every batch-to-batch difference

Run 1 (7 rows): first snapshot, every batch-1 row is inserted.

Batch 1 → 2 (+5 → 12)
- New rows: E03 OPS→LOG and E04 OPS→LOG (bulk reorg; record_updated_at untouched, still versioned);
  E05 Accountant/B3 → Senior Accountant/B4 (one version for two tracked columns);
  E06 absent → termination record; E07 absent → termination record.
- No rows: last_login_at changed for E01–E05; E05's record_updated_at changed (covered by its tracked change).

Batch 2 → 3 (+4 → 16)
- New rows: E01 Engineer II/B3 → Engineer III/B4; E04 absent → termination record;
  E07 reappears (rehire, tracked values identical to before, still a new version);
  E08 new employee.
- No rows: E02 Ben → Benedict and its record_updated_at bump (overwrite + bookkeeping only);
  E03 and E05 last_login_at only; E06 still absent (already has an open termination record);
  last_login_at for everyone; record_updated_at for E01/E07 (their versions come from tracked/rehire logic, not from it).

### Change detection
`strategy: check` with `check_cols: [department_code, job_title, salary_band]`.
- `timestamp` on record_updated_at would miss the May reorg (E03/E04), version E02's name fix,
  and put app timestamps into dbt_valid_from (more than three distinct values).
- `check_cols: all` would version almost every row every night because of last_login_at.

### `hard_deletes`
Chosen: `new_record`. A vanished key gets its window closed and a new row with
`dbt_is_deleted = 'True'`. A rehire closes that row and opens a new `'False'` version.
- `ignore` (default): disappearance is invisible. E06/E07 (run 2) and E04 (run 3) stay open as
  if employed, there is nothing to count, E07's rehire produces nothing, and V6 fails.
- `invalidate`: the open window is closed (dbt_valid_to = R2/R3) but no row is written and no
  `dbt_is_deleted` column exists. Terminations are only "absence of an open row," which cannot
  be counted per department. The snapshot would have 13 rows, and V4 fails for terminated employees.
  E07's rehire would be inserted as a fresh row.

`dbt_is_deleted` is varchar, holding the literal strings `'True'` / `'False'` that dbt writes.
It is not boolean, so accepted_values and every comparison use quoted strings.

### V4: E06's open row
The termination record: E06 | SALES | Account Executive | B3 | dbt_is_deleted 'True' | R2 → open.
```

### Design notes

- **Change detection.** `check` on exactly the three tracked columns is the only setup where a new version happens if and only if a tracked column changed. `record_updated_at` misses the bulk reorg and fires on E02's name correction. Snapshot timing via `snapshot_get_time()` gives every version a `dbt_valid_from` of R1, R2 or R3.
- **Terminations as rows.** `hard_deletes: new_record` turns terminations into rows and rehires into new versions. The flag is a varchar `'True'`/`'False'`, so it is converted into a real boolean once, in `int_d8_employee_history`, and marts only see `is_deleted` and `is_current`.
- **The dim mixes two sources.** dbt never updates an unchanged snapshot row, so the open rows still say "Ben Okafor" and hold old logins. The dim therefore takes version columns from the history (`is_current` drops E04/E06) and overwrite columns from today's dump. It uses a left join from the history, so any history/dump mismatch surfaces in V10 or `not_null` instead of being silently dropped.
- **Agg counts.** The agg pre-aggregates headcount and terminations before joining to the five departments, which avoids fan-out and keeps OPS at 0. It casts both counts to `integer` because DuckDB's `count(*)` returns `BIGINT`. Terminations are counted from the termination record itself, so each one lands in the department held at termination.
- **Test count and syntax.** There is one singular test per V-intent, for 42 assertions in total. V12 counts terminations straight from the snapshot rather than from the intermediate model, so it also checks that model's `is_deleted` mapping. Generic test arguments use the classic top-level form (`values:`, `to:`/`field:`), which parses on dbt 1.9+ where `hard_deletes` exists.