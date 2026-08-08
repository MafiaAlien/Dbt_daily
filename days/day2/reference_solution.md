## `dbt_practice/models/day2/staging/sources.yml`

```yaml
version: 2

sources:
  - name: erp
    description: "Nightly full-snapshot order export dropped by the external ERP system. Not built by dbt."
    schema: main
    # No `database:` key on purpose — the source resolves against whatever
    # database the active target points at.
    tables:
      - name: orders
        identifier: raw_d2_orders
        description: "Full order snapshot. An order is re-sent whenever it is corrected, so ORDER_ID is not unique here."
        loaded_at_field: EXPORTED_AT
        freshness:
          warn_after:
            count: 12
            period: hour
          error_after:
            count: 24
            period: hour
        columns:
          - name: ORDER_ID
            description: "Natural key of the order. Repeats across corrections, so it is NOT unique at this layer."
            data_tests:
              - not_null
          - name: EXPORTED_AT
            description: "Timestamp of the export that carried this version of the row."
            data_tests:
              - not_null
```

## `dbt_practice/models/day2/staging/stg_d2_orders.sql`

```sql
-- Grain: one row per order_id — the row from the latest ERP export of that order.

with source as (

    select * from {{ source('erp', 'orders') }}

),

renamed as (

    select
        cast(ORDER_ID       as integer)       as order_id,
        cast(CUSTOMER_CODE  as varchar)       as customer_id,
        cast(COUNTRY_CODE   as varchar)       as country_code,
        lower(trim(cast(ORDER_STATUS as varchar))) as order_status,
        cast(ORDER_TS       as timestamp)     as ordered_at,
        cast(AMOUNT_USD     as decimal(12,2)) as amount_usd,
        cast(EXPORTED_AT    as timestamp)     as exported_at

    from source

),

ranked as (

    select
        renamed.*,
        row_number() over (
            partition by order_id
            order by exported_at desc
        ) as export_rank

    from renamed

)

select
    order_id,
    customer_id,
    country_code,
    order_status,
    ordered_at,
    amount_usd,
    exported_at

from ranked
where export_rank = 1
```

## `dbt_practice/models/day2/staging/stg_d2_country_region.sql`

```sql
-- Grain: one row per country_code. 1:1 with the seed — no filtering.

with source as (

    select * from {{ ref('raw_d2_country_region') }}

)

select
    cast(country_code as varchar) as country_code,
    cast(region       as varchar) as region

from source
```

## `dbt_practice/models/day2/marts/fct_d2_region_revenue.sql`

```sql
-- Grain: one row per region that at least one order in stg_d2_orders maps to.

with orders as (

    select * from {{ ref('stg_d2_orders') }}

),

country_region as (

    select * from {{ ref('stg_d2_country_region') }}

),

orders_with_region as (

    select
        coalesce(country_region.region, 'Unmapped') as region,
        orders.order_status,
        orders.amount_usd

    from orders
    left join country_region
        on orders.country_code = country_region.country_code

)

select
    region,
    count(*)                                                       as total_order_count,
    count(case when order_status = 'completed' then 1 end)         as completed_order_count,
    cast(
        coalesce(
            sum(case when order_status = 'completed' then coalesce(amount_usd, 0) end),
            0
        ) as decimal(12,2)
    )                                                              as gross_revenue_usd

from orders_with_region
group by region
```

## `dbt_practice/dbt_project.yml` (relevant block — already present, shown for reference)

```yaml
models:
  dbt_practice:
    day2:
      staging:
        +materialized: view
      marts:
        +materialized: table
```

## Design notes

- The `unique` constraint on `order_id` lives on `stg_d2_orders`, not on the source: the ERP export deliberately carries multiple versions of a corrected order, so uniqueness is a property of the deduplicated staging model, not of the raw table.
- Dedup uses `row_number() ... where export_rank = 1` rather than DuckDB's `qualify` clause, so the model runs unchanged on adapters without `QUALIFY`; it also keeps the *whole* winning row rather than mixing columns from different exports the way a per-column `max()` would.
- `'Unmapped'` is produced by `left join` + `coalesce` on the *region*, not by filtering: the join direction (orders on the left) is what makes unmapped orders survive and unordered countries like `MX` never appear.
- `gross_revenue_usd` needs two separate null defenses — the inner `coalesce(amount_usd, 0)` handles order 5004's missing amount, and the outer `coalesce(sum(...), 0)` handles APAC, where the `case` expression is null for every row and `sum` would otherwise return null.
- `count(case ... end)` is used for `completed_order_count` instead of `sum(case ... then 1 else 0 end)` because `count` ignores nulls and returns `0` (never null) for a region with no completed orders, satisfying the `not_null` test without a wrapper.