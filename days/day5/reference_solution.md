Below are the complete files. Nothing outside `models/day5/`, `tests/day5/` is touched; `dbt_project.yml` is left alone and the mart's `incremental` materialization is set in the model's own `config()` block, which wins over the project-level `table`.

---

`dbt_practice/models/day5/staging/stg_d5_shipments.sql`

```sql
{{ config(materialized = 'view') }}

-- Grain: one row per feed row (a shipment state), NOT one row per shipment.
-- Rename and cast only. batch_id is consumed by the filter and not published.

with source as (

    select * from {{ ref('raw_d5_shipments') }}

)

select
    cast(shipment_id       as varchar)       as shipment_id,
    cast(warehouse_code    as varchar)       as warehouse_code,
    cast(ship_date         as date)          as ship_date,
    cast(status            as varchar)       as status,
    cast(shipping_cost_usd as decimal(10,2)) as shipping_cost_usd,
    cast(updated_at        as timestamp)     as updated_at
from source
where batch_id <= {{ var('d5_batch', 1) }}
```

---

`dbt_practice/models/day5/staging/stg_d5_shipment_items.sql`

```sql
{{ config(materialized = 'view') }}

-- Grain: one row per item_id.

with source as (

    select * from {{ ref('raw_d5_shipment_items') }}

)

select
    cast(item_id        as varchar)      as item_id,
    cast(shipment_id    as varchar)      as shipment_id,
    cast(sku            as varchar)      as sku,
    cast(quantity       as integer)      as quantity,
    cast(line_weight_kg as decimal(9,3)) as line_weight_kg
from source
where batch_id <= {{ var('d5_batch', 1) }}
```

---

`dbt_practice/models/day5/staging/schema.yml`

```yaml
version: 2

models:
  - name: stg_d5_shipments
    description: >
      Shipment state log, one row per feed row. A shipment_id appears once per
      status change, distinguished by updated_at. Deliberately no unique test on
      shipment_id: the feed does not promise it and the grain is the feed row.
    columns:
      - name: shipment_id
        data_tests:
          - not_null
      - name: warehouse_code
        data_tests:
          - not_null
      - name: ship_date
        data_tests:
          - not_null
      - name: status
        data_tests:
          - not_null
          - accepted_values:
              values: ['DELIVERED', 'IN_TRANSIT', 'CANCELLED']
      - name: shipping_cost_usd
        description: Header-level cost, charged once per shipment.
        data_tests:
          - not_null
      - name: updated_at
        description: Unique within a shipment_id; the tiebreaker for "latest state".
        data_tests:
          - not_null

  - name: stg_d5_shipment_items
    description: Item lines, one row per item_id, written once.
    columns:
      - name: item_id
        data_tests:
          - unique
          - not_null
      - name: shipment_id
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d5_shipments')
              field: shipment_id
      - name: sku
      - name: quantity
        data_tests:
          - not_null
      - name: line_weight_kg
        data_tests:
          - not_null
```

---

`dbt_practice/models/day5/intermediate/int_d5_shipments_latest.sql`

```sql
-- No config block: inherits the project default (view). One row per surviving
-- shipment. This is the model that collapses the two grains into one, so the
-- mart can be a plain group by with no fan-out.

with shipment_states as (

    select * from {{ ref('stg_d5_shipments') }}

),

ranked_states as (

    -- Portability note: DuckDB supports QUALIFY, but row_number() + a filtering
    -- CTE is used instead so this runs unchanged on Postgres et al.
    select
        shipment_id,
        warehouse_code,
        ship_date,
        status,
        shipping_cost_usd,
        row_number() over (
            partition by shipment_id
            order by updated_at desc
        ) as state_rank
    from shipment_states

),

latest_state as (

    select
        shipment_id,
        warehouse_code,
        ship_date,
        status,
        shipping_cost_usd
    from ranked_states
    where state_rank = 1

),

active_shipments as (

    -- A shipment whose LATEST status is CANCELLED contributes nothing anywhere,
    -- including its item lines, which are dropped by the join below.
    select *
    from latest_state
    where status <> 'CANCELLED'

),

item_totals as (

    select
        shipment_id,
        sum(quantity)       as item_quantity,
        sum(line_weight_kg) as total_weight_kg
    from {{ ref('stg_d5_shipment_items') }}
    group by shipment_id

)

select
    s.shipment_id,
    s.warehouse_code,
    s.ship_date,
    s.status,
    s.shipping_cost_usd,
    cast(coalesce(i.item_quantity, 0)   as integer)       as item_quantity,
    cast(coalesce(i.total_weight_kg, 0) as decimal(12,3)) as total_weight_kg
from active_shipments as s
left join item_totals as i
    on s.shipment_id = i.shipment_id
```

---

`dbt_practice/models/day5/intermediate/schema.yml`

```yaml
version: 2

models:
  - name: int_d5_shipments_latest
    description: >
      One row per non-cancelled shipment, carrying its latest header state and
      its item lines already rolled up to shipment level. Header measures stay
      at header grain; line measures are pre-aggregated, so the mart can sum
      both on one pass without duplicating shipping_cost_usd per item line.
    columns:
      - name: shipment_id
        data_tests:
          - unique
          - not_null
      - name: ship_date
        data_tests:
          - not_null
      - name: warehouse_code
        data_tests:
          - not_null
```

---

`dbt_practice/models/day5/marts/fct_d5_daily_warehouse_shipments.sql`

```sql
{{
    config(
        materialized = 'incremental',
        unique_key = ['ship_date', 'warehouse_code'],
        on_schema_change = 'fail'
    )
}}

-- Grain: one row per (ship_date, warehouse_code).
-- incremental_strategy is deliberately unset; see notes.md.

with shipments as (

    select * from {{ ref('int_d5_shipments_latest') }}

    {% if is_incremental() %}

    -- Recompute every day from the current watermark forward, and recompute it
    -- from the FULL staging history for those days, not just tonight's batch.
    -- ">=" not ">": the feed guarantee allows the tail of the newest day to
    -- arrive late and allows already-delivered shipments on that day to be
    -- restated, so the newest day already in the table must be rebuilt whole.
    where ship_date >= (
        select coalesce(max(ship_date), cast('1900-01-01' as date))
        from {{ this }}
    )

    {% endif %}

)

select
    ship_date,
    warehouse_code,
    cast(count(*) as integer)                                            as shipment_count,
    cast(sum(case when status = 'DELIVERED' then 1 else 0 end)
         as integer)                                                     as delivered_count,
    cast(sum(shipping_cost_usd) as decimal(10,2))                        as shipping_cost_usd,
    cast(sum(item_quantity) as integer)                                  as item_quantity,
    cast(sum(total_weight_kg) as decimal(12,3))                          as total_weight_kg
from shipments
group by ship_date, warehouse_code
```

---

`dbt_practice/models/day5/marts/schema.yml`

```yaml
version: 2

models:
  - name: fct_d5_daily_warehouse_shipments
    description: >
      Daily shipment mart at (ship_date, warehouse_code). Incremental: each run
      rebuilds only the days the newest batch could touch, and rebuilds them
      from the whole feed rather than from the batch alone.
    columns:
      - name: ship_date
        data_tests:
          - not_null
      - name: warehouse_code
        data_tests:
          - not_null
      - name: shipment_count
        data_tests:
          - not_null
      - name: delivered_count
        data_tests:
          - not_null
      - name: shipping_cost_usd
        data_tests:
          - not_null
      - name: item_quantity
        data_tests:
          - not_null
      - name: total_weight_kg
        data_tests:
          - not_null
```

---

`dbt_practice/tests/day5/assert_fct_d5_one_row_per_date_warehouse.sql`

```sql
-- V4: the declared grain. Fails if any (ship_date, warehouse_code) repeats.
select
    ship_date,
    warehouse_code,
    count(*) as row_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
group by ship_date, warehouse_code
having count(*) > 1
```

---

`dbt_practice/tests/day5/assert_fct_d5_shipment_count_at_least_one.sql`

```sql
-- V5: an all-cancelled (date, warehouse) must produce no row, never a zero row.
select
    ship_date,
    warehouse_code,
    shipment_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
where shipment_count is null
   or shipment_count < 1
```

---

`dbt_practice/tests/day5/assert_fct_d5_delivered_count_not_above_shipment_count.sql`

```sql
-- V6: delivered shipments are a subset of counted shipments.
select
    ship_date,
    warehouse_code,
    shipment_count,
    delivered_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
where delivered_count > shipment_count
```

---

`dbt_practice/models/day5/notes.md`

```markdown
# Day 5 — incremental daily warehouse mart

## Grain plan

Three measures are header-grain (`shipment_count`, `delivered_count`,
`shipping_cost_usd`) and two are line-grain (`item_quantity`,
`total_weight_kg`). Joining items to headers and aggregating in one pass would
repeat each header's `shipping_cost_usd` once per item line — S001 has three
lines, so 2026-06-01 / WH-A would report 37.50 + 9.00 instead of 21.50, and
`shipment_count` would become a line count.

So the two grains are collapsed *before* they meet:

1. `stg_d5_shipments` — feed-row grain (9 rows at batch 1, 16 at batch 2).
2. `int_d5_shipments_latest` — shipment grain. Deduplicates to the greatest
   `updated_at` per `shipment_id`, drops shipments whose *latest* status is
   `CANCELLED`, and left-joins item totals that were pre-aggregated to
   `shipment_id`. Because the join is left from active shipments, a cancelled
   shipment's lines disappear with it, and a shipment with no lines gets 0
   rather than NULL via `coalesce`.
3. `fct_d5_daily_warehouse_shipments` — day/warehouse grain. Both header and
   line measures are now one-per-shipment, so a single `group by` is safe.

A (date, warehouse) whose shipments are all cancelled has no surviving rows to
group and therefore emits no row — the "no row of zeros" rule falls out of the
filter rather than needing a `having`.

## What the intermediate buys

It is the only place that knows about supersession and cancellation, and it is
the model that guarantees one row per shipment (tested with `unique`). The mart
is then a pure aggregation, which keeps the incremental predicate readable and
makes the fan-out bug structurally impossible rather than merely avoided.

## Incremental configuration

**Where the config lives.** `dbt_project.yml` sets `day5/marts` to `table` and
is not editable this day. A model-level `config()` block has higher precedence
than a project-level config, so `materialized = 'incremental'` in the model
file overrides it.

**`unique_key = ['ship_date', 'warehouse_code']`.** The mart's grain is the
compound key, so that is the key the incremental logic must match on. Using
`ship_date` alone would delete every warehouse on a recomputed day and reinsert
only the ones present in the new set; using neither would append duplicates.

**`on_schema_change = 'fail'`.** The default is `ignore`, which silently drops
a newly added column from incremental runs until someone notices finance is
missing a measure. `fail` makes a column change a loud, obvious event that
forces a deliberate `--full-refresh` instead of a quietly wrong table. Chosen
over `sync_all_columns` because this is a published contract, not a scratch
model — schema drift here should stop the pipeline, not be absorbed by it.

**`incremental_strategy` unset — the adapter default is `delete+insert`.**
dbt-duckdb implements `duckdb__get_incremental_default_sql`, which returns the
delete+insert SQL when a `unique_key` is configured and plain append when it is
not. Two ways I confirmed it rather than guessing: read that macro in the
installed adapter (`dbt/include/duckdb/macros/materializations/incremental.sql`
inside the dbt-duckdb package), and read the compiled run artifact after run 2
(`target/run/.../fct_d5_daily_warehouse_shipments.sql`), which contains a
`delete from ... using` against the temp relation followed by an `insert into` —
not an `insert`-only append and not a `merge`.

## Which rows tonight recomputes

The mart holds a watermark implicitly: `max(ship_date)` of the existing table.
The feed guarantee says a batch never delivers a shipment whose `ship_date` is
earlier than the newest `ship_date` the previous batch delivered. So every row
tonight's batch can affect has `ship_date >= max(ship_date)` already in the
table, and the predicate is:

```sql
where ship_date >= (select coalesce(max(ship_date), cast('1900-01-01' as date))
                    from {{ this }})
```

Two things about it matter more than the predicate itself:

- **`>=`, not `>`.** The newest day already in the table is exactly the day that
  can still change: 2026-06-03 arrived in batch 1 with S008/S009 in transit and
  is restated in batch 2 (S008 and S009 become `DELIVERED`, S009's header cost
  drops 13.50 → 11.75, S010 and S011 arrive). `>` would leave 2026-06-03 frozen
  at its run-1 values and every test would still pass.
- **The filter is on the day, not on the batch.** Rows for a recomputed day are
  rebuilt from the entire staging history, so 2026-06-03 / WH-A sums S008's
  *and* S010's headers and all four of their item lines. Aggregating only
  batch-2 rows and inserting them would overwrite the day with a partial answer.

Delete+insert then replaces 2026-06-03 WH-A and WH-C, inserts the new
2026-06-03 WH-B and both 2026-06-04 rows, and never touches 2026-06-01 or
2026-06-02. Because the same predicate is a no-op under `--full-refresh`, the
equivalence check reproduces run 2 exactly.

If the watermark day were ever entirely cancelled the mart's `max(ship_date)`
would sit behind the feed's, which widens the recompute window — safe in the
wrong direction, and the extra days recompute to the values they already hold.

## Tests

V4–V6 are singular tests in `tests/day5/` because no built-in generic expresses
them without a package: `unique` cannot take two columns, and neither an
inter-column comparison nor a lower bound has a built-in. They still run on both
runs without being named explicitly — dbt's default indirect selection is
eager, so `--select path:models/day5` pulls in every test whose parents are in
the selection, including singular tests that `ref()` the mart.

(`data_tests:` is the dbt ≥1.8 spelling; on 1.7 and earlier the key is `tests:`.)
```

---

## Design notes

- The mart's `incremental` config sits in the model's `config()` block, which outranks the untouchable `day5/marts: table` in `dbt_project.yml`.
- `int_d5_shipments_latest` collapses feed-row grain to shipment grain and pre-aggregates item lines, so the mart's single `group by` cannot fan out header cost across item lines.
- The incremental predicate is `ship_date >= max(ship_date) from {{ this }}` — `>=` because the watermark day itself is the one still being restated, and it selects *days*, not batches, so a recomputed day is rebuilt from the entire feed.
- `unique_key` is the compound grain, so the adapter default `delete+insert` replaces exactly the recomputed (date, warehouse) pairs; a known limitation is that a pair which becomes entirely cancelled would linger, since delete+insert only deletes keys present in the new set.
- Every measure is explicitly cast at the mart: DuckDB returns `BIGINT` from `count(*)`, `HUGEINT` from `sum(integer)`, and `decimal(38,x)` from `sum(decimal)`, none of which match the required column types.