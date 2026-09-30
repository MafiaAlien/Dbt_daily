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
