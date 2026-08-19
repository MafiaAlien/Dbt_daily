-- C9 (value half): payout_amount is never negative.
select
    payout_id,
    payout_amount
from {{ ref('stg_d4_payouts') }}
where payout_amount < 0
