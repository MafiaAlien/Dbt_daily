-- C14 (value half): line_amount is never negative.
select
    line_id,
    payout_id,
    line_amount
from {{ ref('stg_d4_payout_lines') }}
where line_amount < 0
