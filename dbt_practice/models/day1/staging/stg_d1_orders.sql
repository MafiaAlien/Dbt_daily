with 
orders as (
    select 
        cast(OrderID as integer) as order_id,
        cast(CustomerID as integer) as customer_id,
        cast(OrderTs as timestamp) as ordered_at,
        cast(Amount as decimal(10, 2)) as amount,
        cast(Status as varchar) as status

    from 
        {{ ref('raw_d1_orders') }}
)

select * from orders