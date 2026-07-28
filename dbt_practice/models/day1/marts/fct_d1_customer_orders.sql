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
    customer_name,
    count(*) as order_count,
    sum(case when status = 'completed' then amount else 0 end) as total_amount
from customers c left join orders o on c.customer_id = o.customer_id
group by 1, xss2