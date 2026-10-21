{{ config(materialized='view') }}

with source as (

    select
        PAYMENT_ID,
        INVOICE_ID,
        PAID_AT,
        AMOUNT_USD,
        BATCH_ID
    from {{ ref('raw_d9_payments') }}

),

renamed as (

    select
        cast(PAYMENT_ID as varchar)       as payment_id,
        cast(INVOICE_ID as varchar)       as invoice_id,
        cast(PAID_AT    as timestamp)     as paid_at,
        cast(AMOUNT_USD as decimal(10,2)) as amount_usd,
        cast(BATCH_ID   as integer)       as batch_id
    from source

)

select
    payment_id,
    invoice_id,
    paid_at,
    amount_usd
from renamed
where batch_id <= {{ var('d9_batch', 1) }}
