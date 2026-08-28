{{
    config(
        materialized='incremental',
        unique_key=['ship_date', 'warehouse_code'],
        on_schema_change='fail',
    )
}}

with  cnt_item_quantity_weight as (
    select 
        shipment_id,
        sum(coalesce(quantity,0)) as item_quantity,
        sum(coalesce(line_weight_kg,0)) as total_weight_kg
    from 
        {{ ref('stg_d5_shipment_items') }}
    where shipment_id in (select shipment_id from {{ ref('int_d5_filter_cancelled') }})  
    group by shipment_id
),

most_recent_shipments_without_cancelled as (
    select 
        *,
        row_number()over(partition by shipment_id order by updated_at desc) as _rn 
    from {{ ref('int_d5_filter_cancelled') }}
),

agg as (
    select 
        ship_date,
        warehouse_code,
        count(*) as shipment_count,
        count(case when status='DELIVERED' then 1 end) as delivered_count,
        sum(coalesce(shipping_cost_usd, 0)) as shipping_cost_usd,
        sum(coalesce(item_quantity,0)) as item_quantity,
        sum(coalesce(total_weight_kg, 0)) as total_weight_kg
    from 
        most_recent_shipments_without_cancelled i left join cnt_item_quantity_weight c on i.shipment_id = c.shipment_id 
    where _rn = 1
    group by ship_date, warehouse_code
)

select 
    ship_date,
    warehouse_code,
    coalesce(shipment_count, 0) as shipment_count,
    coalesce(delivered_count, 0) as delivered_count,
    cast(shipping_cost_usd as decimal(10, 2)) as shipping_cost_usd,
    cast(item_quantity as int) as item_quantity,
    cast(total_weight_kg as decimal(12, 3)) as total_weight_kg
from 
    agg