with 
customers as (
    select 
        CustomerID as customer_id,
        FullName as customer_name,
        lower(Email) as email,
        SignupDate as signup_date,
        Country as country
    from {{ ref('raw_d1_customers') }}
)

select * from customers