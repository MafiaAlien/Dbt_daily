-- V12: mart totals equal staging totals (invoice count, billed = all lines, collected = all payments).
-- Reads staging, not the int: see notes.md.
with mart_totals as (

    select
        coalesce(sum(invoice_count), 0) as invoice_count,
        coalesce(sum(billed_usd), 0)    as billed_usd,
        coalesce(sum(collected_usd), 0) as collected_usd
    from {{ ref('fct_d9_daily_plan_revenue') }}

),

staged_invoices as (

    select count(*) as invoice_count
    from {{ ref('stg_d9_invoices') }}

),

staged_lines as (

    select coalesce(sum(amount_usd), 0) as billed_usd
    from {{ ref('stg_d9_invoice_lines') }}

),

staged_payments as (

    select coalesce(sum(amount_usd), 0) as collected_usd
    from {{ ref('stg_d9_payments') }}

),

comparison as (

    select
        'invoice_count'                          as measure,
        cast(m.invoice_count as decimal(18,2))   as mart_total,
        cast(si.invoice_count as decimal(18,2))  as staging_total
    from mart_totals as m
    cross join staged_invoices as si

    union all

    select
        'billed_usd',
        cast(m.billed_usd as decimal(18,2)),
        cast(sl.billed_usd as decimal(18,2))
    from mart_totals as m
    cross join staged_lines as sl

    union all

    select
        'collected_usd',
        cast(m.collected_usd as decimal(18,2)),
        cast(sp.collected_usd as decimal(18,2))
    from mart_totals as m
    cross join staged_payments as sp

)

select
    measure,
    mart_total,
    staging_total
from comparison
where mart_total <> staging_total
