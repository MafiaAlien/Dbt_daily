-- V7: no two rows share (merchant_id, order_month).
select
    merchant_id,
    order_month,
    count(*) as row_count
from {{ ref('fct_d10_merchant_month_payments') }}
group by
    merchant_id,
    order_month
having count(*) > 1
