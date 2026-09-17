with src as (
    select 
        *
    from 
        {{ ref('raw_d6_delivery_adjustments') }}
),

renamed as (
    select 
        cast(ADJUSTMENT_ID as varchar ) as adjustment_id,
        cast(DELIVERY_ID as varchar ) as delivery_id,
        cast(ADJ_TYPE as varchar ) as adj_type,
        cast(ADJ_AMOUNT_USD as decimal(10, 2) ) as adj_amount_usd
    from    
        src 
    where 
        batch_id <= {{ var('d6_batch', 1) }} 
)

select * from renamed