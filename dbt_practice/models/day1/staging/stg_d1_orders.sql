with 
orders as (
    select 
        OrderID as order_id,
        CustomerID as customer_id,
        OrderTs as order_ts,
        Amount as amount,
        Status as status

    from 
        {{ ref('raw_d1_orders') }}
)

select * from orders