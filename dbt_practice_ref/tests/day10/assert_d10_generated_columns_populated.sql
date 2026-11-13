-- V5: every generated column is not null and not negative, on every row.
{%- set prefixes = (var('d10_payment_methods') | map('lower') | list) + ['other'] %}

select
    merchant_id,
    order_month
from {{ ref('fct_d10_merchant_month_payments') }}
where
    {%- for p in prefixes %}
    {{ 'or ' if not loop.first else '' }}{{ p }}_order_count is null
    or {{ p }}_order_count < 0
    or {{ p }}_amount_usd is null
    or {{ p }}_amount_usd < 0
    {%- endfor %}
