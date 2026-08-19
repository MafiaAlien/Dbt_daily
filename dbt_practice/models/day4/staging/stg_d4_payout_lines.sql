with src as (
    select 
        *
    from 
        {{ ref('raw_d4_payout_lines') }}
),

renamed as (
    select 
        cast(LINE_ID as varchar) as line_id,
        cast(PAYOUT_ID as varchar) as payout_id,
        cast(ORDER_REF as varchar) as order_ref,
        cast(CURRENCY as varchar) as currency,
        cast(LINE_AMOUNT as decimal(12, 2)) as line_amount,
        cast(PAYMENT_METHOD as varchar) as payment_method
    from 
        src 
)

select * from renamed 

