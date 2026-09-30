-- V9 Every `order_id` in `stg_d7_orders` appears in the mart exactly once, the mart
-- contains no `order_id` that is not in `stg_d7_orders`, and each row's
-- `order_amount_usd` equals the staging row's.

with orders as (
    select 
        *
    from 
        {{ ref('stg_d7_orders') }}
),

fct as (
    select 
        *
    from 
        {{ ref('fct_d7_attributed') }}
)

-- check if order_id is dup
select 
    order_id,
    'Duplicate order_id in mart' as error_reason
from 
    fct 
where order_id in (select order_id from orders)
group by order_id 
having count(*) > 1

union all 

-- check if order_id in fct does not exit in staging
select 
    f.order_id,
    'order_id in mart does not exist in staging' as error_reason
from fct f
where not exists (select 1 from orders o where f.order_id = o.order_id)

union all

-- check if order amount does not match between fct and staging
select 
    o.order_id,
    'order_amount_usd mismatch' as error_reason
from 
    orders o 
join fct f on o.order_id = f.order_id and o.account_id = f.account_id
where o.order_amount_usd <> f.order_amount_usd
   or (o.order_amount_usd is null and f.order_amount_usd is not null)
   or (o.order_amount_usd is not null and f.order_amount_usd is null)