with agg_lines as (
    select 
        invoice_id,
        sum(amount_usd) as billed_usd
    from    
        {{ ref('stg_d9_invoice_lines') }}
    group by invoice_id
),

agg_payments as (
    select 
        invoice_id,
        sum(amount_usd) as collected_usd
    from 
        {{ ref('stg_d9_payments') }}
    group by invoice_id
),

customers as (
    select 
        customer_id,
        plan_code 
    from 
        {{ ref('stg_d9_customers') }}
)

select 
    i.invoice_id,
    i.customer_id,
    i.invoiced_at,
    strftime(i.invoiced_at, '%Y-%m-%d') as invoice_date,
    c.plan_code,
    cast(coalesce(al.billed_usd, 0) as decimal(12, 2)) as billed_usd,
    cast(coalesce(ap.collected_usd, 0) as decimal(12, 2)) as collected_usd
from 
    {{ ref('stg_d9_invoices') }} i left join customers c on i.customer_id = c.customer_id
    left join agg_lines al on i.invoice_id = al.invoice_id 
    left join agg_payments ap on i.invoice_id = ap.invoice_id