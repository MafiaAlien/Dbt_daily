-- C16: for every payout that has at least one line, payout_amount equals the sum
-- of line_amount over that payout's lines. Payouts with no lines are out of scope,
-- which the inner join expresses. Lines whose payout_id is null or unmatched
-- (L011, L010) never join to a header, so they are neither dropped nor counted here.
with line_totals as (

    select
        payout_id,
        sum(line_amount) as line_total
    from {{ ref('stg_d4_payout_lines') }}
    group by 1

)

select
    p.payout_id,
    p.payout_amount,
    lt.line_total
from {{ ref('stg_d4_payouts') }} p
inner join line_totals lt
    on p.payout_id = lt.payout_id
where p.payout_amount <> lt.line_total
