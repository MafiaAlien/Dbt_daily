-- V6: per-method amounts plus other add up to captured_amount_usd on every row.
{%- set methods = var('d10_payment_methods') | map('lower') | list %}

with totals as (

    select
        merchant_id,
        order_month,
        captured_amount_usd,
        {%- for m in methods %}
        {{ m }}_amount_usd +
        {%- endfor %}
        other_amount_usd as methods_amount_usd
    from {{ ref('fct_d10_merchant_month_payments') }}

)

select
    merchant_id,
    order_month,
    captured_amount_usd,
    methods_amount_usd
from totals
-- null-safe on purpose: a null on either side must fail, not vanish
where captured_amount_usd is distinct from methods_amount_usd
