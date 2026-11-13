with src as (
    select 
        payment_id,
        order_id,
        payment_method,
        status,
        amount_usd,
        paid_at
    from 
        {{ref('raw_d10_payments')}}
),

renamed as (
    select 
        cast( payment_id as varchar) as payment_id,
        cast( order_id as varchar) as order_id,
        cast( payment_method as varchar) payment_method,
        cast( status as varchar) as status,
        cast( amount_usd as decimal(10, 2)) as amount_usd,
        cast( paid_at as timestamp) as paid_at
    from 
        src 
)

select 
    payment_id,
    order_id,
    payment_method,
    status,
    amount_usd,
    paid_at
from 
    renamed