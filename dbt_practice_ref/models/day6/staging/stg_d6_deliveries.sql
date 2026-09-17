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
