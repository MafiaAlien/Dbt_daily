{{ config(materialized='view') }}

select
    cast(order_id as varchar)      as order_id,
    cast(merchant_id as varchar)   as merchant_id,
    cast(ordered_at as timestamp)  as ordered_at
from {{ ref('raw_d10_orders') }}
