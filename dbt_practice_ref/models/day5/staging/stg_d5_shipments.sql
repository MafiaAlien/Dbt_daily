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
