-- V8

with stg as (
    select 
        invoice_id 
    from 
        {{ref('stg_d9_invoices')}}
),

int_tb as (
    select 
        invoice_id,
        count(*) as row_cnt 
    from
        {{ref('int_d9_invoice_revenue')}}
    group by invoice_id
),

compared as (
select 
    coalesce(stg.invoice_id, int_tb.invoice_id) as invoice_id,
    case
            when stg.invoice_id is null then 'in int_d9_invoice_revenue, missing from stg_d9_invoices'
            when int_tb.invoice_id is null then 'in stg_d9_invoices, not in int_d9_invoice_revenue'
            when int_tb.row_cnt > 1        then 'duplicated in int'
        end as failure
from 
    stg full outer join int_tb on stg.invoice_id = int_tb.invoice_id
)

select invoice_id, failure
from compared
where failure is not null