with src as (
    select 
        *
    from {{ ref('raw_d7_orders') }}
),

renamed as (
    select 
        cast(ORDER_ID as varchar) as order_id,
        cast(ACCOUNT_ID as varchar) as account_id,
        cast(ORDER_TS as timestamp) as order_ts,
        cast(ORDER_AMOUNT_USD as decimal(10, 2)) as order_amount_usd
    from 
        src 
)

select * from renamed 