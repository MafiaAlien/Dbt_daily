with 
customers AS (
    select 
        *
    from 
        {{ ref('stg_d1_customers') }}
),

orders as (
    select 
        *
    from {{ ref('stg_d1_orders') }}
)

select
    c.customer_id,
    c.customer_name,
    count(o.order_id) as order_count,
    cast(sum(coalesce(o.amount, 0)) as decimal(10, 2)) as total_amount
from customers c left join orders o on c.customer_id = o.customer_id
group by 1, 2
