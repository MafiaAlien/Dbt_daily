{% set methods = var('d10_payment_methods') | map('lower') | list %}
{% set amount_type = 'decimal(12, 2)' %}


with captured_orders as (
select 
    payment_id,
    order_id,
    merchant_id,
    order_month,
    lower(trim(payment_method)) as payment_method,
    amount_usd 
from 
    {{ref('int_d10_captured_payments')}}
),

agg as (
select 
    merchant_id,
    order_month,
    coalesce(count(*), 0) as order_count,
    cast(coalesce(sum(amount_usd), 0.00) as {{ amount_type }}) as captured_amount_usd,
    {% for method in methods %}
        coalesce(count(case when payment_method = '{{ method }}' then 1 end), 0) as {{ method }}_order_count,
        cast(coalesce(sum(case when payment_method = '{{ method }}' then amount_usd else 0.00 end), 0.00) as {{ amount_type }}) as {{ method }}_amount_usd,
    {% endfor %}
    coalesce(count(case when payment_method is null or payment_method not in ( '{{ methods | join("','") }}' ) then 1 end), 0) as other_order_count,
    cast(coalesce(sum(case when payment_method is null or payment_method not in ( '{{ methods | join("','") }}') then amount_usd else 0 end), 0) as {{ amount_type }}) as other_amount_usd
from 
    captured_orders
group by merchant_id, order_month)

select 
    merchant_id,
    order_month,
    order_count,
    captured_amount_usd,
    {% for method in methods %}
    {{ method }}_order_count,
    {{ method }}_amount_usd,
    {% endfor %}
    other_order_count,
    other_amount_usd
from 
    agg
order by order_month, merchant_id