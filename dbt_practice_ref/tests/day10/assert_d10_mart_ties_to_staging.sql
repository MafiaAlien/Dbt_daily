-- V8: mart totals tie out to staging (deliberately not to the int).
with mart as (

    select
        coalesce(sum(order_count), 0)          as order_count,
        coalesce(sum(captured_amount_usd), 0)  as captured_amount_usd
    from {{ ref('fct_d10_merchant_month_payments') }}

),

staged_orders as (

    select count(*) as order_count
    from {{ ref('stg_d10_orders') }}

),

staged_payments as (

    select coalesce(sum(amount_usd), 0) as captured_amount_usd
    from {{ ref('stg_d10_payments') }}
    where status = 'captured'

)

select
    mart.order_count                     as mart_order_count,
    staged_orders.order_count            as staging_order_count,
    mart.captured_amount_usd             as mart_captured_amount_usd,
    staged_payments.captured_amount_usd  as staging_captured_amount_usd
from mart
cross join staged_orders
cross join staged_payments
where mart.order_count <> staged_orders.order_count
    or mart.captured_amount_usd <> staged_payments.captured_amount_usd
