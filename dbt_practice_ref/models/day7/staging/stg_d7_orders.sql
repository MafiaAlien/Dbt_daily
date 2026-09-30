-- Materialization: view (also set by the day7.staging block in dbt_project.yml)
{{ config(materialized='view') }}

-- Grain: one row per order_id. Static feed, not batched.
select
    cast(ORDER_ID         as varchar)       as order_id,
    cast(ACCOUNT_ID       as varchar)       as account_id,
    cast(ORDER_TS         as timestamp)     as order_ts,
    cast(ORDER_AMOUNT_USD as decimal(10,2)) as order_amount_usd
from {{ ref('raw_d7_orders') }}
