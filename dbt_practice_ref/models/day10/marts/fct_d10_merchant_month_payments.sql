{{ config(materialized='table') }}

{#- The only place the method list comes from. Lower-cased to match staging. -#}
{%- set methods = var('d10_payment_methods') | map('lower') | list -%}

with orders as (

    select
        order_id,
        merchant_id,
        -- date_trunc('month', ts) works on DuckDB/Postgres/Snowflake; BigQuery: date_trunc(date(ts), month)
        cast(date_trunc('month', ordered_at) as date) as order_month
    from {{ ref('stg_d10_orders') }}

),

merchant_months as (

    select
        merchant_id,
        order_month,
        count(*) as order_count
    from orders
    group by
        merchant_id,
        order_month

),

captured as (

    select
        merchant_id,
        order_month,
        order_id,
        payment_method,
        amount_usd,
        {%- if methods %}
        -- a missing method is "other"; the explicit null check is needed because null not in (...) is null
        (
            payment_method is null
            or payment_method not in ({{ "'" ~ methods | join("', '") ~ "'" }})
        ) as is_other_method
        {%- else %}
        true as is_other_method
        {%- endif %}
    from {{ ref('int_d10_captured_payments') }}

),

payment_metrics as (

    select
        merchant_id,
        order_month,
        sum(amount_usd) as captured_amount_usd,
        {%- for m in methods %}
        count(distinct case when payment_method = '{{ m }}' then order_id end) as {{ m }}_order_count,
        sum(case when payment_method = '{{ m }}' then amount_usd end) as {{ m }}_amount_usd,
        {%- endfor %}
        count(distinct case when is_other_method then order_id end) as other_order_count,
        sum(case when is_other_method then amount_usd end) as other_amount_usd
    from captured
    group by
        merchant_id,
        order_month

)

select
    merchant_months.merchant_id,
    merchant_months.order_month,
    cast(merchant_months.order_count as integer) as order_count,
    cast(coalesce(payment_metrics.captured_amount_usd, 0) as decimal(12, 2)) as captured_amount_usd,
    {%- for m in methods %}
    cast(coalesce(payment_metrics.{{ m }}_order_count, 0) as integer) as {{ m }}_order_count,
    cast(coalesce(payment_metrics.{{ m }}_amount_usd, 0) as decimal(12, 2)) as {{ m }}_amount_usd,
    {%- endfor %}
    cast(coalesce(payment_metrics.other_order_count, 0) as integer) as other_order_count,
    cast(coalesce(payment_metrics.other_amount_usd, 0) as decimal(12, 2)) as other_amount_usd
from merchant_months
left join payment_metrics
    on merchant_months.merchant_id = payment_metrics.merchant_id
    and merchant_months.order_month = payment_metrics.order_month
