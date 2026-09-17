Below are the complete files for Day 6.

## Layer 1 — staging

`dbt_practice/models/day6/staging/stg_d6_deliveries.sql`

```sql
{{ config(materialized='view') }}

-- Write-once header feed: exactly one row per delivery_id, ever.
-- Rename and cast only; the only filter is the batch boundary.

select
    cast(delivery_id      as varchar)       as delivery_id,
    cast(courier_id       as varchar)       as courier_id,
    cast(city_code        as varchar)       as city_code,
    cast(delivery_date    as date)          as delivery_date,
    cast(status           as varchar)       as status,
    cast(payout_base_usd  as decimal(10,2)) as payout_base_usd,
    cast(loaded_at        as timestamp)     as loaded_at

from {{ ref('raw_d6_deliveries') }}

where batch_id <= {{ var('d6_batch', 1) }}
```

`dbt_practice/models/day6/staging/stg_d6_delivery_adjustments.sql`

```sql
{{ config(materialized='view') }}

-- Line feed: 0..n rows per delivery. An adjustment always arrives in the
-- same batch as its delivery, so the same batch filter keeps the two aligned.

select
    cast(adjustment_id   as varchar)       as adjustment_id,
    cast(delivery_id     as varchar)       as delivery_id,
    cast(adj_type        as varchar)       as adj_type,
    cast(adj_amount_usd  as decimal(10,2)) as adj_amount_usd

from {{ ref('raw_d6_delivery_adjustments') }}

where batch_id <= {{ var('d6_batch', 1) }}
```

`dbt_practice/models/day6/staging/schema.yml`

```yaml
version: 2

models:
  - name: stg_d6_deliveries
    description: >
      One row per delivery_id. Append-only, write-once header feed: a delivery
      is written once, when it is finalised, and is never restated. Filtered to
      batch_id <= var('d6_batch').
    columns:
      - name: delivery_id
        description: Business key. Unique because the feed is write-once.
        data_tests:
          - unique
          - not_null
      - name: courier_id
        description: Courier who performed the delivery.
      - name: city_code
        description: City the delivery was performed in. Mart grain component.
        data_tests:
          - not_null
      - name: delivery_date
        description: Service date. Mart grain component.
        data_tests:
          - not_null
      - name: status
        description: Final status at the moment the delivery was written.
        data_tests:
          - not_null
          - accepted_values:
              values: ['COMPLETED', 'RETURNED', 'CANCELLED']
      - name: payout_base_usd
        description: Header-level base payout, paid once per delivery.
        data_tests:
          - not_null
      - name: loaded_at
        description: Timestamp of the nightly load that delivered this row.
        data_tests:
          - not_null

  - name: stg_d6_delivery_adjustments
    description: >
      One row per adjustment_id. Zero, one or several lines per delivery.
      Filtered to batch_id <= var('d6_batch').
    columns:
      - name: adjustment_id
        data_tests:
          - unique
          - not_null
      - name: delivery_id
        description: Foreign key to stg_d6_deliveries. No orphan lines exist.
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d6_deliveries')
              field: delivery_id
      - name: adj_type
        data_tests:
          - not_null
          - accepted_values:
              values: ['TIP', 'SURGE', 'PENALTY']
      - name: adj_amount_usd
        description: Signed line amount; penalties are negative.
        data_tests:
          - not_null
```

## Layer 2 — intermediate

`dbt_practice/models/day6/intermediate/int_d6_delivery_payouts.sql`

```sql
-- No dbt_project.yml entry for day6/intermediate, so this inherits the
-- project default and materializes as a view.

-- Collapses the line feed to delivery grain BEFORE it ever meets the header
-- feed. This is the whole point of the model: the header amount must not be
-- multiplied by the number of adjustment lines the delivery happens to own.

with deliveries as (

    select *
    from {{ ref('stg_d6_deliveries') }}
    where status <> 'CANCELLED'   -- cancelled deliveries leave the pipeline here,
                                  -- and take their adjustment lines with them

),

adjustments_by_delivery as (

    select
        delivery_id,
        sum(adj_amount_usd) as adjustment_total_usd
    from {{ ref('stg_d6_delivery_adjustments') }}
    group by delivery_id

)

select
    d.delivery_id,
    d.courier_id,
    d.city_code,
    d.delivery_date,
    d.status,
    cast(d.payout_base_usd as decimal(10,2))              as payout_base_usd,
    cast(coalesce(a.adjustment_total_usd, 0) as decimal(10,2)) as adjustment_total_usd

from deliveries d
left join adjustments_by_delivery a
       on d.delivery_id = a.delivery_id
```

`dbt_practice/models/day6/intermediate/schema.yml`

```yaml
version: 2

models:
  - name: int_d6_delivery_payouts
    description: >
      One row per non-cancelled delivery, with its adjustment lines already
      summed to delivery grain. Exists so the mart aggregates a single grain.
    columns:
      - name: delivery_id
        data_tests:
          - unique
          - not_null
      - name: city_code
        data_tests:
          - not_null
      - name: delivery_date
        data_tests:
          - not_null
      - name: status
        data_tests:
          - not_null
          - accepted_values:
              values: ['COMPLETED', 'RETURNED']
      - name: payout_base_usd
        description: Header amount, carried through unchanged — never re-summed.
        data_tests:
          - not_null
      - name: adjustment_total_usd
        description: Sum of the delivery's adjustment lines; 0 when it has none.
        data_tests:
          - not_null
```

## Layer 3 — mart

`dbt_practice/models/day6/marts/fct_d6_daily_city_payouts.sql`

```sql
{{ config(
    unique_key=['delivery_date', 'city_code'],
    incremental_strategy='delete+insert',
    on_schema_change='fail'
) }}

-- materialized: incremental comes from dbt_project.yml (day6/marts).

with scoped as (

    select *
    from {{ ref('int_d6_delivery_payouts') }}

    {% if is_incremental() %}

    -- LATE ARRIVALS. A delivery loads no later than 4 calendar days after its
    -- delivery_date, and no delivery_date is ever later than its own load date.
    -- So every row in tonight's batch has delivery_date >= (load date - 4), and
    -- the mart's own max delivery_date is <= that load date. Therefore nothing
    -- can arrive below (mart max delivery_date - 4): that is a safe lookback.
    --
    -- Every date inside the window is recomputed IN FULL from staging, which
    -- holds all batches <= d6_batch, not just from tonight's rows. Combined with
    -- delete+insert on the grain, the window is replaced wholesale rather than
    -- added to, so a reopened day lands at its complete value.
    and_this_is_a_filter_placeholder_removed_below
    {% endif %}

)

select 1
```

Correction — here is the actual file (the block above was a drafting artifact; use this):

```sql
{{ config(
    unique_key=['delivery_date', 'city_code'],
    incremental_strategy='delete+insert',
    on_schema_change='fail'
) }}

-- materialized: incremental is set in dbt_project.yml (day6/marts), not here.

with scoped as (

    select *
    from {{ ref('int_d6_delivery_payouts') }}

    {% if is_incremental() %}

    -- LATE ARRIVALS. A delivery loads no later than 4 calendar days after its
    -- delivery_date, and a delivery_date is never later than its own load date.
    -- So every row in tonight's batch has delivery_date >= (load date - 4), and
    -- the mart's max delivery_date is <= that load date. Nothing can therefore
    -- arrive below (mart max delivery_date - 4): a safe, closed lookback window.
    --
    -- Every date inside the window is recomputed IN FULL from staging, which
    -- holds every batch <= d6_batch — not only tonight's rows. Combined with
    -- delete+insert on the grain, the window is replaced wholesale rather than
    -- appended to, so a reopened day lands at its complete value.
    --
    -- DuckDB: date - integer subtracts days. Portable alternative:
    --   dateadd('day', -4, max(delivery_date))
    where delivery_date >= (
        select coalesce(max(delivery_date), date '1900-01-01') - 4
        from {{ this }}
    )

    {% endif %}

),

agg as (

    select
        delivery_date,
        city_code,
        count(*)                                                as delivery_count,
        sum(case when status = 'COMPLETED' then 1 else 0 end)   as completed_count,
        sum(payout_base_usd)                                    as payout_base_usd,
        sum(adjustment_total_usd)                               as adjustment_total_usd
    from scoped
    group by delivery_date, city_code

)

select
    delivery_date,
    city_code,
    cast(delivery_count      as integer)       as delivery_count,
    cast(completed_count     as integer)       as completed_count,
    cast(payout_base_usd     as decimal(10,2)) as payout_base_usd,
    cast(adjustment_total_usd as decimal(10,2)) as adjustment_total_usd,
    cast(payout_base_usd + adjustment_total_usd as decimal(10,2)) as total_payout_usd
from agg
```

`dbt_practice/models/day6/marts/schema.yml`

```yaml
version: 2

models:
  - name: fct_d6_daily_city_payouts
    description: >
      Daily city-level courier payout mart, one row per (delivery_date,
      city_code). Incremental with a 4-day lookback so days that reopen are
      recomputed in full. Cancelled deliveries are excluded entirely; a pair
      whose deliveries are all cancelled produces no row.
    columns:
      - name: delivery_date
        description: Grain component.
        data_tests:
          - not_null
      - name: city_code
        description: Grain component.
        data_tests:
          - not_null
      - name: delivery_count
        description: Non-cancelled deliveries on that date in that city.
        data_tests:
          - not_null
      - name: completed_count
        description: Of those, the ones whose status is COMPLETED.
        data_tests:
          - not_null
      - name: payout_base_usd
        description: Header-level base payout, summed once per delivery.
        data_tests:
          - not_null
      - name: adjustment_total_usd
        description: Line-level adjustments, summed. 0 when there are none.
        data_tests:
          - not_null
      - name: total_payout_usd
        description: payout_base_usd + adjustment_total_usd.
        data_tests:
          - not_null
```

## Singular tests

`dbt_practice/tests/day6/assert_d6_payouts_one_row_per_date_city.sql`

```sql
-- V4: no two mart rows share the same (delivery_date, city_code).

select
    delivery_date,
    city_code,
    count(*) as row_count
from {{ ref('fct_d6_daily_city_payouts') }}
group by delivery_date, city_code
having count(*) > 1
```

`dbt_practice/tests/day6/assert_d6_payouts_delivery_count_at_least_one.sql`

```sql
-- V5: every published row represents at least one delivery.

select
    delivery_date,
    city_code,
    delivery_count
from {{ ref('fct_d6_daily_city_payouts') }}
where delivery_count < 1
```

`dbt_practice/tests/day6/assert_d6_payouts_completed_not_above_delivery_count.sql`

```sql
-- V6: completed deliveries are a subset of counted deliveries.

select
    delivery_date,
    city_code,
    delivery_count,
    completed_count
from {{ ref('fct_d6_daily_city_payouts') }}
where completed_count > delivery_count
```

`dbt_practice/tests/day6/assert_d6_payouts_reconcile_to_staging_both_ways.sql`

```sql
-- V7: the reconciliation, in both directions.
--   * every (delivery_date, city_code) with >= 1 non-cancelled delivery in
--     staging has exactly one mart row, with a matching delivery_count;
--   * the mart has no row for a pair with no such deliveries.
-- The FULL OUTER JOIN is what makes the second direction detectable: a row the
-- mart never wrote is invisible to any test that starts from the mart.

with expected as (

    select
        delivery_date,
        city_code,
        count(*) as delivery_count
    from {{ ref('stg_d6_deliveries') }}
    where status <> 'CANCELLED'
    group by delivery_date, city_code

),

actual as (

    select
        delivery_date,
        city_code,
        count(*)            as mart_row_count,
        max(delivery_count) as delivery_count
    from {{ ref('fct_d6_daily_city_payouts') }}
    group by delivery_date, city_code

)

select
    coalesce(e.delivery_date, a.delivery_date) as delivery_date,
    coalesce(e.city_code,     a.city_code)     as city_code,
    e.delivery_count                           as expected_delivery_count,
    a.delivery_count                           as mart_delivery_count,
    a.mart_row_count
from expected e
full outer join actual a
    on  e.delivery_date = a.delivery_date
    and e.city_code     = a.city_code
where a.delivery_date is null          -- staging pair the mart never wrote
   or e.delivery_date is null          -- mart row with nothing behind it
   or a.mart_row_count <> 1            -- not exactly one row
   or e.delivery_count <> a.delivery_count
```

`dbt_practice/tests/day6/assert_d6_payouts_total_equals_base_plus_adjustments.sql`

```sql
-- V8: the published total is internally consistent, exactly.

select
    delivery_date,
    city_code,
    payout_base_usd,
    adjustment_total_usd,
    total_payout_usd
from {{ ref('fct_d6_daily_city_payouts') }}
where total_payout_usd <> payout_base_usd + adjustment_total_usd
```

## notes.md

`dbt_practice/models/day6/notes.md`

```markdown
# Day 6 — late-arriving facts

## Grain plan

| grain | what lives there | model |
|---|---|---|
| one row per `adjustment_id` | `adj_amount_usd` | `stg_d6_delivery_adjustments` |
| one row per `delivery_id` | `payout_base_usd` (header), `status` | `stg_d6_deliveries` |
| one row per `delivery_id` | header amount + summed line amounts | `int_d6_delivery_payouts` |
| one row per (`delivery_date`, `city_code`) | all five measures | `fct_d6_daily_city_payouts` |

Four of the five measures are header-grain (`delivery_count`, `completed_count`,
`payout_base_usd`, and the header half of `total_payout_usd`); `adjustment_total_usd`
is line-grain. Joining the two feeds first and aggregating afterwards would repeat the
header row once per adjustment line: `D005` owns three lines, so `payout_base_usd` for
2026-07-01 CT-B would read 14.00 + 7.75 + 7.75 = 29.50. So the line feed is collapsed to
delivery grain *first*, in `int_d6_delivery_payouts`, and the mart then aggregates a
single grain from one row per delivery. Nothing in V1–V8 catches that fan-out: the counts
stay right, and `total = base + adjustments` stays true of the inflated numbers.

## What the intermediate model buys

One place where the two grains meet, one `left join` that can fan out, and a testable
assertion (`unique` on `delivery_id`) that it did not. The mart's `from` clause then has
no join in it at all.

## Config decisions

- **`unique_key = ['delivery_date', 'city_code']`** — the mart's grain, so the key the
  incremental run must replace on. A single-column key would be wrong: a date spans
  several cities, and a city spans several dates.
- **`incremental_strategy = 'delete+insert'`** — dbt-duckdb's adapter default is
  `delete+insert`, so this **matches** the default rather than overriding it; it is
  written out because "settled by accident" and "settled on purpose" look identical in a
  diff six months from now. `append` would double-count every reopened day. The strategy
  matters more than usual here: the incremental batch is a *recomputed replacement* for
  its dates, not a delta to add.
- **`on_schema_change = 'fail'`** — default is `ignore`. Finance reconciles this table
  against a bank file; a column silently appearing, disappearing or changing type is a
  reconciliation break, and stopping the run is cheaper than publishing a drifted table.

## Late arrivals — the lookback

`delivery_date >= (select max(delivery_date) from {{ this }}) - 4`.

The bound is the SLA, not a guess. A delivery loads no later than 4 calendar days after
its `delivery_date`, and no `delivery_date` is later than its own load date. So for
tonight's load date `L`: every new row has `delivery_date >= L - 4`, and the mart's
`max(delivery_date)` is `<= L`, hence `L - 4 >= max(delivery_date) - 4`. Nothing can
arrive below the window. (If a date's deliveries were all cancelled, the mart holds no
row for it and its `max` sits lower — which widens the window, never narrows it.)

Run 3 is the proof: the mart's max is 2026-07-03, the window opens at 2026-06-29, and
`D015`/`D016` (2026-07-01) and `D017` (2026-07-03) all fall inside it. Every date in the
window is then recomputed **in full** from staging — which holds all batches `<= d6_batch`,
not only tonight's — so 2026-07-01 CT-A is rebuilt from all four of its deliveries rather
than topped up, and 2026-07-01 CT-C is written for the first time. That is why the
incremental result equals the `--full-refresh` result cell for cell.

## Why `unique` on `delivery_id` this day and not on Day 5

Day 5's header feed restated rows: the same business key could arrive again in a later
batch, so the raw stream legitimately held several rows per key and only the deduplicated
model was unique. This feed is **write-once** — exactly one row per `delivery_id`, ever,
final at write time, never restated. The uniqueness is a property of the feed itself, so
it belongs on the staging model as a test.

## Note on YAML

Tests are declared under `data_tests:`. The older `tests:` key is equivalent on dbt 1.8+
but deprecated.
```

## Design notes

- The header feed is collapsed against the line feed at **delivery grain in the intermediate model**, never in the mart's `from` clause. The fan-out that would otherwise multiply `payout_base_usd` by a delivery's adjustment count passes every one of V1–V8 — it is the trap that only cell comparison catches.
- The incremental predicate is a **4-day lookback derived from the stated SLA**, not from the newest batch: `max(delivery_date) - 4` is provably below any arriving row, because a delivery's own date never exceeds its load date.
- The window is **recomputed in full from staging and replaced via `delete+insert`**, not appended to. That is what makes run 3 equal a `--full-refresh` at the same `d6_batch`: a reopened day is rewritten from all of its deliveries, and a pair the mart never had (2026-07-01 CT-C) is created rather than missed.
- Cancellation is applied once, in `int_d6_delivery_payouts`, before the join — which drops a cancelled delivery's adjustment lines automatically instead of requiring a second filter downstream.
- V7 uses a `full outer join` deliberately: the direction that starts from staging is the only one that can see a row the mart never wrote, and it also asserts `mart_row_count = 1` so "exactly one row" is covered independently of V4.