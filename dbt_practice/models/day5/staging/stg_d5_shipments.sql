with src as (
    select 
        *
    from 
        {{ ref('raw_d5_shipments') }}
),

stg_d5_shipments as (
	select
		cast(SHIPMENT_ID as varchar) as shipment_id,
		cast(WAREHOUSE_CODE as varchar) as warehouse_code,
		cast(SHIP_DATE as date) as ship_date,
		cast(STATUS as varchar) as status,
		cast(SHIPPING_COST_USD as decimal(10, 2)) as shipping_cost_usd,
		cast(UPDATED_AT as timestamp) as updated_at
	from 
        src 
	where batch_id <= {{ var('d5_batch', 1) }}
)

select *
from stg_d5_shipments
