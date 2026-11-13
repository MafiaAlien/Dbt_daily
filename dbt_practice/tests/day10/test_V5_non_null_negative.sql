/* **V5 — mart, intent: every generated column is populated.** For every method in
`var('d10_payment_methods')`, and for `other`: `{m}_order_count` and `{m}_amount_usd` are not
null and not negative, on every row. One singular test, one file, written as a loop over the
var. When run 2 adds a method, V5 covers its two columns with no edit.
*/

{% set methods = var('d10_payment_methods') | map('lower') | list + ['other'] %}

{% for method in methods %}
select 
    '{{ method }}' as column_name,
    {{ method }}_order_count,
    {{ method }}_amount_usd
from 
    {{ref('fct_d10_merchant_month_payments')}}
where 
    ({{ method }}_order_count is null or {{ method }}_order_count < 0)
    and ({{ method }}_amount_usd is null or {{ method }}_amount_usd < 0)
{% if not loop.last %} union all {% endif %}
{% endfor %}