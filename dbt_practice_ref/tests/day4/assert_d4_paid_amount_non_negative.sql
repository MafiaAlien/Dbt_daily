-- C19: paid_amount in the mart is never negative.
select
    seller_id,
    paid_amount
from {{ ref('fct_d4_seller_payouts') }}
where paid_amount < 0
