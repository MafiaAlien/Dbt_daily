with customers as (

    select * from {{ ref('stg_d1_customers') }}

),

orders as (

    select * from {{ ref('stg_d1_orders') }}

),

-- Aggregate first, at order grain, so the join below cannot fan out customers.
-- Guest checkouts (null customer_id) are dropped here: they belong to no customer.
order_agg as (

    select
        customer_id,
        count(*)                  as order_count,
        sum(coalesce(amount, 0))  as total_amount

    from orders
    where customer_id is not null
    group by customer_id

),

final as (

    select
        customers.customer_id,
        customers.customer_name,
        coalesce(order_agg.order_count, 0)                          as order_count,
        cast(coalesce(order_agg.total_amount, 0) as decimal(10, 2)) as total_amount

    from customers
    left join order_agg
        on customers.customer_id = order_agg.customer_id

)

select * from final
