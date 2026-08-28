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
