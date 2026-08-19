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

lines_per_payout as (

    select
        payout_id,
        count(*) as line_count
    from {{ ref('stg_d4_payout_lines') }}
    group by 1

),

agg_payouts as (
    select 
        p.seller_id,
        coalesce(count(*),0) as payout_count,
        sum(case when p.status = 'PAID' then 1 else 0 end) as paid_payout_count,
        sum(case when p.status = 'PAID' then coalesce(p.payout_amount, 0) else 0 end) as paid_amount,
        coalesce(sum(l.line_count), 0) as line_count
    from 
        payout p left join lines_per_payout l on p.payout_id = l.payout_id
    group by p.seller_id
)

select 
    a.seller_id, 
    s.seller_name,
    a.payout_count,
    a.paid_payout_count,
    cast(a.paid_amount as decimal(12, 2)) as paid_amount,
    a.line_count 
from 
    agg_payouts a left join sellers s on a.seller_id = s.seller_id