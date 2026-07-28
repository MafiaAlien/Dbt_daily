with 
customers as (
    select 
        cast(CustomerID as integer) as customer_id,
        cast(FullName as varchar) as customer_name,
        lower(cast(Email as varchar)) as email,
        cast(SignupDate as date) as signup_date,
        cast(Country as varchar) as country
    from {{ ref('raw_d1_customers') }}
)

select * from customers