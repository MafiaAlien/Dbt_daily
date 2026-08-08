-- Grain: one row per region that at least one order in stg_d2_orders maps to.

with orders as (

    select * from {{ ref('stg_d2_orders') }}

),

country_region as (

    select * from {{ ref('stg_d2_country_region') }}

),

orders_with_region as (

    select
        coalesce(country_region.region, 'Unmapped') as region,
        orders.order_status,
        orders.amount_usd

    from orders
    left join country_region
        on orders.country_code = country_region.country_code

)

select
    region,
    count(*)                                                       as total_order_count,
    count(case when order_status = 'completed' then 1 end)         as completed_order_count,
    cast(
        coalesce(
            sum(case when order_status = 'completed' then coalesce(amount_usd, 0) end),
            0
        ) as decimal(12,2)
    )                                                              as gross_revenue_usd

from orders_with_region
group by region
