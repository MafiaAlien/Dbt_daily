with src as (
    select 
        *
    from {{ ref('raw_d5_shipment_items') }}
), 

renamed as (
select
	cast(ITEM_ID as varchar) as item_id,
	cast(SHIPMENT_ID as varchar) as shipment_id,
	cast(SKU as varchar) as sku,
	cast(QUANTITY as integer) as quantity,
	cast(LINE_WEIGHT_KG as decimal(9, 3)) as line_weight_kg
from src
where batch_id <= {{ var('d5_batch', 1) }} 
)

select * from renamed 