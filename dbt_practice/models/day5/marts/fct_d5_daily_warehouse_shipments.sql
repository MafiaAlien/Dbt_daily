{{
    config(
        materialized='incremental',
        unique_key=['ship_date', 'warehouse_code'],
        on_schema_change='fail',
    )
}}

with latest_shipments as (
    select * from {{ ref('int_d5_shipments_latest') }}
    {% if is_incremental() %}
        where ship_date >= (select coalesce(max(ship_date), cast('1900-01-01' as date)) from {{ this }})
    {% endif %}
),

agg as (
    select 
        ship_date,
        warehouse_code,
        count(*) as shipment_count,
        count(case when status='DELIVERED' then 1 end) as delivered_count,
        sum(coalesce(shipping_cost_usd, 0.00)) as shipping_cost_usd,
        sum(coalesce(item_quantity,0)) as item_quantity,
        sum(coalesce(total_weight_kg, 0.000)) as total_weight_kg
    from 
        latest_shipments
    group by ship_date, warehouse_code
)

select 
    ship_date,
    warehouse_code,
    cast(coalesce(shipment_count, 0) as integer) as shipment_count,
    cast(coalesce(delivered_count, 0) as integer) as delivered_count,
    cast(shipping_cost_usd as decimal(10, 2)) as shipping_cost_usd,
    cast(item_quantity as int) as item_quantity,
    cast(total_weight_kg as decimal(12, 3)) as total_weight_kg
from 
    agg