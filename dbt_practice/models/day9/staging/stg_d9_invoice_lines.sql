with src as (
    select 
        *
    from 
        {{ ref('raw_d9_invoice_lines')}}
),

renamed as (
    select 
        cast(LINE_ID as varchar) as line_id,
        cast(INVOICE_ID as varchar) as invoice_id,
        cast(LINE_TYPE as varchar) as line_type,
        cast(AMOUNT_USD as decimal(10, 2)) as amount_usd,
        cast(BATCH_ID as integer) as batch_id
    from 
        src
)

select 
    line_id,
    invoice_id,
    line_type,
    amount_usd
from 
    renamed
where batch_id = {{ var('d9_batch', 1) }}