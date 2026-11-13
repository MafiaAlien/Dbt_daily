/*
**V7 — mart, intent: the grain.** No two rows share (`merchant_id`, `order_month`).
*/

select
    merchant_id,
    order_month
from {{ ref('fct_d10_merchant_month_payments') }}
group by merchant_id, order_month
having count(*) > 1