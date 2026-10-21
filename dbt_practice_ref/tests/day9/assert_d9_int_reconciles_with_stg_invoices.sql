-- V8: every staged invoice appears in the int exactly once, and the int has no invoice staging lacks.
with staged as (

    select invoice_id
    from {{ ref('stg_d9_invoices') }}

),

modeled as (

    select
        invoice_id,
        count(*) as row_count
    from {{ ref('int_d9_invoice_revenue') }}
    group by invoice_id

)

select
    coalesce(s.invoice_id, m.invoice_id) as invoice_id,
    case
        when s.invoice_id is null then 'in int, not in staging'
        when m.invoice_id is null then 'in staging, missing from int'
        else 'appears ' || cast(m.row_count as varchar) || ' times in int'
    end as failure
from staged as s
full outer join modeled as m
    on m.invoice_id = s.invoice_id
where s.invoice_id is null
   or m.invoice_id is null
   or m.row_count <> 1
