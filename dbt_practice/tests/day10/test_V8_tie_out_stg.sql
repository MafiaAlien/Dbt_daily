/*
**V8 — mart, intent: totals tie out to staging.** `sum(order_count)` equals the row count of
`stg_d10_orders`, and `sum(captured_amount_usd)` equals the sum of `amount_usd` over captured
payments in `stg_d10_payments`. It reads **staging**, not the int. Say in `notes.md` why.

V5–V8 must be part of `dbt build`, so they run on **both** runs.
*/

{% set amount_type = 'decimal(12, 2)' %}


with stg as (
    select 
    o.merchant_id,
    {{dbt.date_trunc('month', 'o.order_at')}} as order_month,
    count(p.order_id) as stg_cnt
    cast(coalesce(sum(p.amount_usd), 0) as {{ amount_type }}) as stg_amount_usd
from 
    {{ref('stg_d10_payments')}} p left join {{ref('stg_d10_orders')}} o on p.order_id = o.order_id
where p.status = 'captured')
group by 
    o.merchant_id,
    {{dbt.date_trunc('month', 'o.order_at')}}

fct_orders_payments as (
    select  
        merchant_id,
        order_month,
        order_count as fct_cnt,
        captured_amount_usd as fct_amount_usd
    from 
        {{ ref('fct_day10_merchant_month_payments') }}
)


select  
    coalesce(f.merchant_id, s.merchant_id) as merchant_id,
    coalesce(f.order_month, s.order_month) as order_month,
from 
    fct_orders_payments f full outer join stg s on f.merchant_id = s.merchant_id and f.order_month = s.order_month
where 
    (f.fct_amount_usd is distinct from s.stg_amount_usd) or (f.fct_cnt is distinct from s.stg_cnt)