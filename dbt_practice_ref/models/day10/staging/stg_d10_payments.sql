{{ config(materialized='view') }}

select
    cast(payment_id as varchar)                          as payment_id,
    cast(order_id as varchar)                            as order_id,
    -- a blank method stays missing (NULL); staging never substitutes a label
    nullif(lower(cast(payment_method as varchar)), '')   as payment_method,
    cast(status as varchar)                              as status,
    cast(amount_usd as decimal(10, 2))                   as amount_usd,
    cast(paid_at as timestamp)                           as paid_at
from {{ ref('raw_d10_payments') }}
