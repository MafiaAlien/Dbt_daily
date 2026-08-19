-- C15: every payout whose status is PAID has at least one payout line.
-- Payouts in any other status may legitimately have none, so they are not checked.
select
    p.payout_id,
    p.seller_id,
    p.status
from {{ ref('stg_d4_payouts') }} p
left join {{ ref('stg_d4_payout_lines') }} l
    on p.payout_id = l.payout_id
where p.status = 'PAID'
group by p.payout_id, p.seller_id, p.status
having count(l.line_id) = 0
