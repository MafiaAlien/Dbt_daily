with src as (
    select 
        *
    from 
        {{ ref('raw_d4_payouts') }}
),

renamed as (
    select 
        cast(PAYOUT_ID as varchar ) as payout_id,
        cast(SELLER_ID as varchar) as seller_id,
        cast(PAYOUT_DATE as date) as payout_date,
        cast(STATUS as varchar) as status,
        cast(CURRENCY as varchar) as currency,
        cast(payout_amount as decimal(12, 2)) as payout_amount
    from 
        src 
)

select * from renamed 

