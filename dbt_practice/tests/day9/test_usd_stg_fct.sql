/* 
**V12 — mart, intent: totals tie out to staging.** `sum(invoice_count)` equals the row count
of `stg_d9_invoices`; `sum(billed_usd)` equals the sum of `stg_d9_invoice_lines.amount_usd`;
`sum(collected_usd)` equals the sum of `stg_d9_payments.amount_usd`. It reads **staging**,
not the int. Say in `notes.md` why.
*/

with stg_bill as (
    select 
        cast(coalesce(sum(billed_usd), 0) as decimal(12, 2)) as stg_billed_amount
    from 
        {{ ref('stg_d9_invoice_lines')}}
    group by invoice_id 
),

stg_collected as (
    select 
        cast(coalesce(sum(collected_usd), 0) as decimal(12, 2)) as stg_collected_usd
    from 
        {{ ref('stg_d9_payments')}}
    group by invoice_id 
),

stg_row_cnt as (
    select 
        count(invoice_id ) as stg_row
    from 
        {{ ref('stg_d9_invoices') }}
    
),

fct as (
select 
    sum(invoice_count) as fct_row,
    cast(sum(billed_usd) as decimal(12 ,2)) as fct_billed_usd,
    cast(sum(collected_usd) as decimal(12, 2)) as fct_collected_usd
from
    {{ ref('fct_d9daily_plan_revenue') }}
)

select 
    *
from 
    fct f,
    stg_bill b,
    stg_collected c,
    stg_row_cnt r 
where 
    f.fct_row is distinct from r.stg_row 
    or f.fct_billed_usd is distinct from b.stg_billed_amount
    or f.fct_collected_usd is distinct from c.stg_collected_usd