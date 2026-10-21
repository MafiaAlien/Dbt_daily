{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['invoice_date', 'plan_code'],
        on_schema_change='fail',
    )
}}

with latest_invoice as (
    select 
        *
    from 
        {{ ref('int_d9_invoice_revenue') }}
    {% if is_incremental() %}
    where invoice_date >= (select coalesce(max(invoice_date), '1900-01-01') - interval '4 days' from {{ this }})
    {% endif %}
),

agg as (
    select 
        invoice_date,
        plan_code,
        cast(coalesce(count(invoice_id), 0) as integer) as invoice_count,
        cast(coalesce(sum(billed_usd), 0) as decimal(12, 2)) as billed_usd,
        cast(coalesce(sum(collected_usd), 0) as decimal(12 ,2)) as collected_usd
    from 
        latest_invoice
    group by invoice_date, plan_code
)

select 
    *,
    cast((billed_usd - collected_usd) as decimal(12, 2)) as outstanding_usd
from 
    agg 
where invoice_count >= 1
