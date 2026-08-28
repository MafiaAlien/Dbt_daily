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
