with src as(
    select 
        *
    from 
        {{ref('raw_d9_invoices')}}

),

renamed as (
    select 
        cast(INVOICE_ID as varchar) as invoice_id,
        cast(CUSTOMER_ID as varchar) as customer_id,
        cast(INVOICED_AT as timestamp) as invoiced_at,
        cast(BATCH_ID as integer) as batch_id
    from 
        src 
)

select 
    invoice_id,
    customer_id,
    invoiced_at
from 
    renamed
where 
    batch_id = {{ var('d9_batch', 1) }}