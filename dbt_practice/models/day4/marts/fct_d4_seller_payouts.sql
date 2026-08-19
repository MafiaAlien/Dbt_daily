with payout as (
    select 
        *
    from 
        {{ ref('stg_d4_payouts') }}
),

sellers as (
    select 
        *
    from 
        {{ ref('stg_d4_sellers') }}
),

payout_lines as (
    select 
        *
    from 
        {{ ref('stg_d4_payout_lines') }}
),

agg_payouts as (
    select 
        p.seller_id,
        coalesce(count(*),0) as payout_count,
        sum(case when p.status = 'PAID' then 1 else 0 end) as paid_payout_count,
        sum(case when p.status = 'PAID' then coalesce(p.payout_amount, 0) else 0 end)paid_amount,
        coalesce(count(line_id), 0) as line_count
    from 
        payout p left join payout_lines pl on p.payout_id = pl.payout_id
    group by p.seller_id
)

select 
    a.seller_id, 
    s.seller_name,
    a.payout_count,
    a.paid_payout_count,
    a.paid_amount,
    a.line_count 
from 
    agg_payouts a left join sellers s on a.seller_id = s.seller_id