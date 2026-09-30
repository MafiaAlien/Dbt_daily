Below are the complete files for Day 7. There are 12 files: 5 models, 4 YAML files, 5 singular tests and `notes.md`. The only functions used are standard ones (`row_number`, `coalesce`, `is distinct from`), so there are no DuckDB-specific call-outs.

Materialization is set by the existing `day7:` block in `dbt_project.yml`, which I did not edit. I also repeat it in each staging and mart model with `config()`, so the choice is visible where the SQL lives. The intermediate model has no config on purpose, so it gets dbt's default of `view`.

---

### Staging

`dbt_practice/models/day7/staging/stg_d7_account_versions.sql`
```sql
-- Materialization: view (also set by the day7.staging block in dbt_project.yml)
{{ config(materialized='view') }}

-- Grain: one row per (account_id, updated_at). Rename and cast only.
select
    cast(ACCOUNT_ID     as varchar)   as account_id,
    cast(ACCOUNT_NAME   as varchar)   as account_name,
    cast(CONTRACT_TIER  as varchar)   as contract_tier,
    cast(BILLING_REGION as varchar)   as billing_region,
    cast(ACCOUNT_STATUS as varchar)   as account_status,
    cast(UPDATED_AT     as timestamp) as updated_at
from {{ ref('raw_d7_account_versions') }}
where batch_id <= {{ var('d7_batch', 1) }}
```

`dbt_practice/models/day7/staging/stg_d7_orders.sql`
```sql
-- Materialization: view (also set by the day7.staging block in dbt_project.yml)
{{ config(materialized='view') }}

-- Grain: one row per order_id. Static feed, not batched.
select
    cast(ORDER_ID         as varchar)       as order_id,
    cast(ACCOUNT_ID       as varchar)       as account_id,
    cast(ORDER_TS         as timestamp)     as order_ts,
    cast(ORDER_AMOUNT_USD as decimal(10,2)) as order_amount_usd
from {{ ref('raw_d7_orders') }}
```

`dbt_practice/models/day7/staging/schema.yml`
```yaml
version: 2

models:
  - name: stg_d7_account_versions
    description: >
      Append-only account version feed, filtered to the simulated batch boundary.
      Grain: one row per (account_id, updated_at). Composite grain, so no unique test here.
    columns:
      - name: account_id
        data_tests:
          - not_null
      - name: account_name
        data_tests:
          - not_null
      - name: contract_tier
        data_tests:
          - not_null
          - accepted_values:
              values: ['STANDARD', 'PREMIUM', 'ENTERPRISE']
      - name: billing_region
        data_tests:
          - not_null
      - name: account_status
        data_tests:
          - not_null
          - accepted_values:
              values: ['ACTIVE', 'CHURNED']
      - name: updated_at
        data_tests:
          - not_null

  - name: stg_d7_orders
    description: Orders. Static, one row per order_id, never restated.
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: account_id
        data_tests:
          - not_null
      - name: order_ts
        data_tests:
          - not_null
      - name: order_amount_usd
        data_tests:
          - not_null
```

### Intermediate

`dbt_practice/models/day7/intermediate/int_d7_account_feed_latest.sql`
```sql
-- No config on purpose: no dbt_project.yml entry for this folder, so dbt's default (view) applies.
-- Grain: one row per account_id, the latest version visible to the current batch.
-- This is the snapshot's relation; a snapshot must see exactly one row per unique_key.
with ranked as (

    select
        account_id,
        account_name,
        contract_tier,
        billing_region,
        account_status,
        updated_at,
        row_number() over (
            partition by account_id
            order by updated_at desc
        ) as version_rank
    from {{ ref('stg_d7_account_versions') }}

)

select
    account_id,
    account_name,
    contract_tier,
    billing_region,
    account_status,
    updated_at
from ranked
where version_rank = 1
```

`dbt_practice/models/day7/intermediate/schema.yml`
```yaml
version: 2

models:
  - name: int_d7_account_feed_latest
    description: >
      Current state of each account as of the current batch. Grain: one row per account_id.
      Versions superseded within the same batch are dropped here and never reach the snapshot.
    columns:
      - name: account_id
        data_tests:
          - unique
          - not_null
```

### Snapshot

`dbt_practice/snapshots/day7/snap_d7_accounts.yml`
```yaml
snapshots:
  - name: snap_d7_accounts
    description: >
      SCD2 history of accounts, built one nightly run at a time from
      int_d7_account_feed_latest. Not reproducible from source; never full-refresh.
    relation: ref('int_d7_account_feed_latest')
    config:
      strategy: timestamp
      unique_key: account_id
      updated_at: updated_at
      # dbt_valid_to_current left at its default: the current version has dbt_valid_to = NULL.
    columns:
      - name: account_id
        data_tests:
          - not_null
      - name: contract_tier
        data_tests:
          - not_null
          - accepted_values:
              values: ['STANDARD', 'PREMIUM', 'ENTERPRISE']
      - name: dbt_valid_from
        data_tests:
          - not_null
```

### Marts

`dbt_practice/models/day7/marts/dim_d7_accounts_current.sql`
```sql
-- Materialization: table (also set by the day7.marts block in dbt_project.yml)
{{ config(materialized='table') }}

-- Grain: one row per account whose CURRENT version is ACTIVE.
-- Both predicates apply to the same row: first "is the current version",
-- then "that current version is ACTIVE". A churned account's older ACTIVE
-- versions are closed (dbt_valid_to not null), so they can never qualify.
select
    account_id,
    account_name,
    contract_tier,
    billing_region,
    dbt_valid_from as current_since
from {{ ref('snap_d7_accounts') }}
where dbt_valid_to is null
  and account_status = 'ACTIVE'
```

`dbt_practice/models/day7/marts/fct_d7_orders_attributed.sql`
```sql
-- Materialization: table (also set by the day7.marts block in dbt_project.yml)
{{ config(materialized='table') }}

-- Grain: one row per order_id in stg_d7_orders (all of them, always).
with orders as (

    select order_id, account_id, order_ts, order_amount_usd
    from {{ ref('stg_d7_orders') }}

),

account_history as (

    -- dbt_scd_id and dbt_updated_at deliberately not selected.
    select account_id, contract_tier, billing_region, dbt_valid_from, dbt_valid_to
    from {{ ref('snap_d7_accounts') }}

),

current_accounts as (

    select account_id, contract_tier
    from {{ ref('dim_d7_accounts_current') }}

)

select
    o.order_id,
    o.account_id,
    o.order_ts,
    o.order_amount_usd,
    cast(coalesce(h.contract_tier,  'UNKNOWN') as varchar) as tier_at_order,
    cast(coalesce(h.billing_region, 'UNKNOWN') as varchar) as region_at_order,
    cast(coalesce(c.contract_tier,  'UNKNOWN') as varchar) as current_tier
from orders as o
-- As-of-then attribution: half-open window [dbt_valid_from, dbt_valid_to),
-- NULL dbt_valid_to = open. The predicate lives in the ON clause so an order with
-- no covering version (before the first version) survives with NULLs -> UNKNOWN.
left join account_history as h
    on  h.account_id = o.account_id
    and o.order_ts >= h.dbt_valid_from
    and (h.dbt_valid_to is null or o.order_ts < h.dbt_valid_to)
-- Current attribution: a different question, a different join.
left join current_accounts as c
    on  c.account_id = o.account_id
```

`dbt_practice/models/day7/marts/schema.yml`
```yaml
version: 2

models:
  - name: dim_d7_accounts_current
    description: One row per currently active account. Churned accounts produce no row.
    columns:
      - name: account_id
        data_tests:
          - unique
          - not_null
      - name: account_name
        data_tests:
          - not_null
      - name: contract_tier
        data_tests:
          - not_null
      - name: billing_region
        data_tests:
          - not_null
      - name: current_since
        data_tests:
          - not_null

  - name: fct_d7_orders_attributed
    description: >
      One row per order. tier_at_order / region_at_order come from the snapshot version
      in effect at order_ts ([valid_from, valid_to)); current_tier comes from the current dim.
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: account_id
        data_tests:
          - not_null
      - name: order_ts
        data_tests:
          - not_null
      - name: order_amount_usd
        data_tests:
          - not_null
      - name: tier_at_order
        data_tests:
          - not_null
          - accepted_values:
              values: ['STANDARD', 'PREMIUM', 'ENTERPRISE', 'UNKNOWN']
      - name: region_at_order
        data_tests:
          - not_null
      - name: current_tier
        data_tests:
          - not_null
```

### Singular tests

`dbt_practice/tests/day7/assert_snap_d7_accounts_exactly_one_current_row_per_account.sql`
```sql
-- V5: every account_id has EXACTLY one open row (dbt_valid_to is null) — zero is a failure too.
select
    account_id,
    sum(case when dbt_valid_to is null then 1 else 0 end) as open_rows
from {{ ref('snap_d7_accounts') }}
group by account_id
having sum(case when dbt_valid_to is null then 1 else 0 end) <> 1
```

`dbt_practice/tests/day7/assert_snap_d7_accounts_windows_no_overlap_no_empty.sql`
```sql
-- V6: SCD2 integrity. Windows are [dbt_valid_from, dbt_valid_to), NULL dbt_valid_to = open.
-- Fails on (a) an empty or inverted window, (b) any two windows of one account that overlap —
-- including exact duplicates, which is why rows are numbered rather than compared by dbt_scd_id.
with windows as (

    select
        account_id,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (
            partition by account_id
            order by dbt_valid_from, dbt_valid_to
        ) as window_seq
    from {{ ref('snap_d7_accounts') }}

),

empty_windows as (

    select
        account_id,
        'empty_window'                as failure,
        dbt_valid_from                as window_a_from,
        dbt_valid_to                  as window_a_to,
        cast(null as timestamp)       as window_b_from,
        cast(null as timestamp)       as window_b_to
    from windows
    where dbt_valid_to is not null
      and dbt_valid_to <= dbt_valid_from

),

overlapping_windows as (

    select
        a.account_id,
        'overlap'                     as failure,
        a.dbt_valid_from              as window_a_from,
        a.dbt_valid_to                as window_a_to,
        b.dbt_valid_from              as window_b_from,
        b.dbt_valid_to                as window_b_to
    from windows as a
    join windows as b
        on  a.account_id = b.account_id
        and a.window_seq < b.window_seq
    -- half-open intervals overlap iff each starts before the other ends
    where (b.dbt_valid_to is null or a.dbt_valid_from < b.dbt_valid_to)
      and (a.dbt_valid_to is null or b.dbt_valid_from < a.dbt_valid_to)

)

select * from empty_windows
union all
select * from overlapping_windows
```

`dbt_practice/tests/day7/assert_fct_d7_orders_attributed_reconciles_to_stg_d7_orders.sql`
```sql
-- V9: both directions in one test. A full outer join makes a missing mart row visible
-- (m.order_id is null) instead of silently comparing against NULL.
with stg as (

    select order_id, order_amount_usd
    from {{ ref('stg_d7_orders') }}

),

mart as (

    select
        order_id,
        count(*)              as mart_rows,
        min(order_amount_usd) as min_amount,
        max(order_amount_usd) as max_amount
    from {{ ref('fct_d7_orders_attributed') }}
    group by order_id

)

select
    coalesce(s.order_id, m.order_id) as order_id,
    case
        when s.order_id is null then 'in_mart_not_in_staging'
        when m.order_id is null then 'in_staging_not_in_mart'
        when m.mart_rows <> 1   then 'duplicated_in_mart'
        else 'amount_mismatch'
    end                              as failure,
    s.order_amount_usd               as staging_amount,
    m.min_amount,
    m.max_amount,
    m.mart_rows
from stg as s
full outer join mart as m
    on s.order_id = m.order_id
where s.order_id is null
   or m.order_id is null
   or m.mart_rows <> 1
   or m.min_amount is distinct from s.order_amount_usd
   or m.max_amount is distinct from s.order_amount_usd
```

`dbt_practice/tests/day7/assert_fct_d7_orders_attributed_unknown_tier_only_without_covering_version.sql`
```sql
-- V10: no row is UNKNOWN while a snapshot version covering its order_ts exists.
-- Uses the reference definition of "in effect": [dbt_valid_from, dbt_valid_to), NULL = open.
select
    f.order_id,
    f.account_id,
    f.order_ts,
    s.contract_tier  as covering_tier,
    s.dbt_valid_from as covering_from,
    s.dbt_valid_to   as covering_to
from {{ ref('fct_d7_orders_attributed') }} as f
join {{ ref('snap_d7_accounts') }} as s
    on  s.account_id = f.account_id
    and f.order_ts >= s.dbt_valid_from
    and (s.dbt_valid_to is null or f.order_ts < s.dbt_valid_to)
where f.tier_at_order = 'UNKNOWN'
```

`dbt_practice/tests/day7/assert_fct_d7_orders_attributed_current_tier_matches_dim.sql`
```sql
-- V11: current_tier equals the dim's contract_tier when the account is in the dim,
-- and is 'UNKNOWN' exactly when it is not. Null-safe comparisons throughout, so a NULL
-- current_tier fails instead of slipping through a <> comparison.
select
    f.order_id,
    f.account_id,
    f.current_tier,
    d.contract_tier as dim_tier
from {{ ref('fct_d7_orders_attributed') }} as f
left join {{ ref('dim_d7_accounts_current') }} as d
    on d.account_id = f.account_id
where (d.account_id is null     and f.current_tier is distinct from 'UNKNOWN')
   or (d.account_id is not null and f.current_tier is distinct from d.contract_tier)
```

### Notes

`dbt_practice/notes.md`
```markdown
# Day 7 notes

## Test count (written before run 1)

Expected: **39** assertions.

| Item | Assertions | Count |
|---|---|---|
| V1 stg_d7_account_versions | not_null x6, accepted_values x2 | 8 |
| V2 stg_d7_orders | unique + not_null order_id, not_null x3 | 5 |
| V3 int_d7_account_feed_latest | unique + not_null account_id | 2 |
| V4 snap_d7_accounts | not_null x3, accepted_values x1 | 4 |
| V5 singular | exactly one open row per account | 1 |
| V6 singular | no overlap / no empty window | 1 |
| V7 dim_d7_accounts_current | unique + not_null x5 | 6 |
| V8 fct_d7_orders_attributed | unique, not_null x7 (order_id's not_null counted once), accepted_values | 9 |
| V9 singular | reconciliation, both directions | 1 |
| V10 singular | UNKNOWN only without covering version | 1 |
| V11 singular | current_tier agrees with dim | 1 |
| **Total** | | **39** |

`dbt ls --resource-type test ...` must print 39 lines. If it prints fewer, a YAML patch
did not bind (misspelled model name), or a singular test sits outside tests/day7.

## Why no `unique` on stg_d7_account_versions.account_id

On the staging model account_id legitimately repeats because its grain is
(account_id, updated_at) — A100 has three versions by batch 3 — so `unique` would fail
by design. On int_d7_account_feed_latest one row per account_id is exactly the
precondition the snapshot depends on, so there `unique` is the guard.

## Snapshots in dbt 1.9

Before 1.9 a snapshot was a Jinja `{% snapshot %}...{% endsnapshot %}` block wrapping a
select, configured with `config()` inside it and required to hard-code `target_schema`.
From 1.9, snapshots are declared in YAML under `snapshots:`: a `relation:` (a ref or
source) plus a `config:`. `target_schema`/`target_database` became optional, so snapshots
follow normal schema resolution like models. The same release added
`snapshot_meta_column_names`, `dbt_valid_to_current` and `hard_deletes`.

I would not write the legacy form in a new project. It buries transformation SQL inside
the one object that cannot be rebuilt, where it can't be tested before it writes history.
Its hard-coded target schema also fights dev/prod separation. The YAML form pushes the
SQL into an ordinary, tested model (int_d7_account_feed_latest) and leaves the snapshot
as pure configuration. The legacy block is still supported, but only as a legacy path.

## Debrief prep

- Q2 — the lost version: A200 / PREMIUM / AMER @ 2026-03-15 08:00. It landed in batch 3
  together with A200 ENTERPRISE @ 2026-03-22. int_d7_account_feed_latest keeps only the
  latter, so the snapshot never saw PREMIUM. The cell it decides is O-006
  (2026-03-18 09:00), which is attributed STANDARD, not PREMIUM. Passing both rows to the
  snapshot would not have saved it: two candidate rows for one key in one run corrupts
  the history. V5/V6 exist to catch that.
- Q4 — if tier_at_order equals current_tier everywhere, tier_at_order was joined to the
  current version (dim, or `dbt_valid_to is null`) instead of the version in effect at
  order_ts. It is the "same join" trap, and it stays green.
- Generic `accepted_values` uses the top-level `values:` form, which works on every dbt
  version that supports YAML snapshots. Newer releases may print a deprecation notice
  suggesting `arguments:`; that notice is not a test WARN.
```

---

### Design notes

- **Timestamp strategy on `updated_at`, not `check`.** This makes `dbt_valid_from`/`dbt_valid_to` the operational change instants rather than the wall-clock time of each run. The expected tables are built from those source timestamps, and a `check` strategy would stamp run times instead.
- **Half-open windows `[dbt_valid_from, dbt_valid_to)`, NULL means open.** An order exactly on an interior boundary (O-002, O-013) belongs to the version that starts there. The version that ends there excludes it via `<`, and the one that starts includes it via `>=`, so exactly one matches. The start is inclusive at a first version too (O-011). V10 re-derives coverage with the same predicate, so a predicate that is merely too narrow goes red.
- **The window predicate lives in the `ON` clause of a `LEFT JOIN`.** An inner join, or the same predicate in `WHERE`, silently drops O-010, which was placed before A400's first version. V9's full outer join is what turns that red. Because V6 guarantees non-overlapping windows, the left join can't fan out, and V9 would also catch a duplicate.
- **The dim applies "current version" and "is ACTIVE" to the same row.** Using "latest ACTIVE version per account" instead would resurrect A300 from its pre-churn row. That mistake passes every generic test and only shows when you compare cells. `tier_at_order` deliberately uses the churned version's attributes (O-009 is PREMIUM), because attribution asks what the account was on at the time, not whether it is still a customer.
- **`current_tier` comes from `dim_d7_accounts_current`, not the snapshot's open row.** That is why A300 is `UNKNOWN` on the right while being known on the left. It is also what V11 pins down, with `is distinct from` so that a NULL cannot pass a `<>` comparison.