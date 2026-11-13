{{ config(materialized='view') }}

with payments as (

    select
        payment_id,
        order_id,
        payment_method,
        amount_usd
    from {{ ref('stg_d10_payments') }}
    where status = 'captured'

),

orders as (

    select
        order_id,
        merchant_id,
        -- month of the ORDER, not of paid_at.
        -- date_trunc('month', ts) works on DuckDB/Postgres/Snowflake; BigQuery: date_trunc(date(ts), month)
        cast(date_trunc('month', ordered_at) as date) as order_month
    from {{ ref('stg_d10_orders') }}

)

select
    payments.payment_id,
    payments.order_id,
    orders.merchant_id,
    orders.order_month,
    payments.payment_method,
    payments.amount_usd
from payments
inner join orders
    on payments.order_id = orders.order_id
