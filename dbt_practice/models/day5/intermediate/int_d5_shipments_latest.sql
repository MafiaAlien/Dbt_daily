{{ config(materialized='view') }}

with src as (
    select 
        *
    from 
        {{ ref('stg_d5_shipments') }}
   
),

dedup_rn as (
    select
        *,
        row_number()over(partition by shipment_id order by updated_at desc) as _rn 
    from 
        src  
),

non_cancelled as (
select 
    *
from 
    dedup_rn 
where 
    status <> 'CANCELLED' and _rn = 1
),


cnt_item_quantity_weight as (
    select 
        shipment_id,
        sum(coalesce(quantity,0)) as item_quantity,
        sum(coalesce(line_weight_kg,0)) as total_weight_kg
    from 
        {{ ref('stg_d5_shipment_items') }} 
    group by shipment_id
)

select 
    n.shipment_id,
    warehouse_code,
    ship_date,
    status,
    shipping_cost_usd,
    cast(coalesce(item_quantity, 0) as integer) as item_quantity,
    cast(coalesce(total_weight_kg, 0.000) as decimal(12, 3)) as total_weight_kg
from 
    non_cancelled n left join cnt_item_quantity_weight c on n.shipment_id = c.shipment_id