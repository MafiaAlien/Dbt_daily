with src as (
    select 
        *
    from 
        {{ ref('raw_d6_deliveries') }}
),

renamed as (
    select 
        cast(DELIVERY_ID as varchar) as delivery_id,
        cast(COURIER_ID as varchar) as courier_id,
        cast(CITY_CODE as varchar ) as city_code,
        cast(DELIVERY_DATE as date) as delivery_date,
        cast(STATUS as varchar) as status,
        cast(PAYOUT_BASE_USD as decimal(10, 2)) as payout_base_usd,
        cast(LOADED_AT as timestamp) as loaded_at 
    from 
        src 
    where 
        batch_id <= {{ var('d6_batch', 1) }} 

)

select * from renamed