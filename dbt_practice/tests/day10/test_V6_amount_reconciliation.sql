/*
**V6 — mart, intent: the methods partition the money.** On every row, the sum of every
`{m}_amount_usd` plus `other_amount_usd` equals `captured_amount_usd`. One singular test,
generated from the same var.
*/

{% set methods = var('d10_payment_methods') | map('lower') | list + ['other'] %}

with pivoted as (
select 
    merchant_id,
    order_month,
    {% for m in methods %}
        coalesce({{m}}_amount_usd, 0)
        {% if not loop.last %} + {% endif %}
    {% endfor %} as pivoted_total
from 
    {{ref('fct_d10_merchant_month_payments')}}
    ),

src as (
    select 
        merchant_id,
        order_month,
        coalesce(sum(amount_usd), 0.00) as source_total
    from 
    {{ref('int_d10_captured_payments')}}
    group by 
        merchant_id,
        order_month
)

select
    coalesce(p.merchant_id, s.merchant_id) as merchant_id,
    p.pivoted_total,
    s.source_total,
    p.pivoted_total - s.source_total as diff
from pivoted p
full outer join src s
    on p.merchant_id = s.merchant_id and p.order_month = s.order_month
where p.merchant_id is null
   or s.merchant_id is null
   or abs(p.pivoted_total - s.source_total) > 0.01