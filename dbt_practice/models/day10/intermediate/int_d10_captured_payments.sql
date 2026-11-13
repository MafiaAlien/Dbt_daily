select 
    p.payment_id,
    p.order_id,
    o.merchant_id,
    {{dbt.date_trunc('month', 'o.ordered_at')}} as order_month,
    p.payment_method,
    p.amount_usd 
from 
    {{ref('stg_d10_payments')}} p left join {{ref('stg_d10_orders')}} o on p.order_id = o.order_id
where p.status = 'captured'