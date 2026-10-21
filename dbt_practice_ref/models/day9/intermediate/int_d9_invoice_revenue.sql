{{ config(materialized='view') }}

with invoices as (

    select
        invoice_id,
        customer_id,
        invoiced_at
    from {{ ref('stg_d9_invoices') }}

),

-- collapse lines to the invoice grain BEFORE joining: lines x payments would fan out
invoice_lines as (

    select
        invoice_id,
        sum(amount_usd) as billed_usd
    from {{ ref('stg_d9_invoice_lines') }}
    group by invoice_id

),

invoice_payments as (

    select
        invoice_id,
        sum(amount_usd) as collected_usd
    from {{ ref('stg_d9_payments') }}
    group by invoice_id

),

customer_versions as (

    select
        customer_id,
        plan_code,
        dbt_valid_from,
        dbt_valid_to
    from {{ ref('snap_d9_customers') }}

)

select
    i.invoice_id,
    i.customer_id,
    i.invoiced_at,
    cast(i.invoiced_at as date)                          as invoice_date,
    v.plan_code,
    cast(l.billed_usd as decimal(12,2))                  as billed_usd,
    cast(coalesce(p.collected_usd, 0) as decimal(12,2))  as collected_usd
from invoices as i
-- half-open window [from, to): an invoice stamped at the exact edit instant belongs to the new version.
-- left join keeps the grain; an unattributable invoice surfaces as a null plan_code (V7 / V9 fire).
left join customer_versions as v
    on  v.customer_id = i.customer_id
    and v.dbt_valid_from <= i.invoiced_at
    and (v.dbt_valid_to is null or i.invoiced_at < v.dbt_valid_to)
left join invoice_lines as l
    on l.invoice_id = i.invoice_id
left join invoice_payments as p
    on p.invoice_id = i.invoice_id
