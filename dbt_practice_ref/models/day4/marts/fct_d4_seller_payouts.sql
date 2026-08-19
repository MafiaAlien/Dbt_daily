{{ config(materialized='table') }}

with payouts as (

    select * from {{ ref('stg_d4_payouts') }}

),

sellers as (

    select * from {{ ref('stg_d4_sellers') }}

),

-- Lines are collapsed to payout grain BEFORE the header join, so the header-grain
-- counts (payout_count, paid_payout_count, paid_amount) cannot be fanned out by lines.
-- No filter here: the null-payout_id line and the P9999 line simply form groups that
-- match no header, so they contribute to nothing without being dropped.
lines_per_payout as (

    select
        payout_id,
        count(*) as line_count
    from {{ ref('stg_d4_payout_lines') }}
    group by 1

),

payouts_with_lines as (

    select
        p.seller_id,
        p.payout_id,
        p.status,
        p.payout_amount,
        coalesce(l.line_count, 0) as line_count
    from payouts p
    left join lines_per_payout l
        on p.payout_id = l.payout_id

),

seller_agg as (

    select
        seller_id,
        count(*)                                     as payout_count,
        count(case when status = 'PAID' then 1 end)  as paid_payout_count,
        cast(
            coalesce(sum(case when status = 'PAID' then payout_amount end), 0)
            as decimal(12,2)
        )                                            as paid_amount,
        cast(sum(line_count) as bigint)              as line_count
    from payouts_with_lines
    group by 1

)

-- Grain is driven by payouts, not by the seller master, so the join to sellers is a
-- left join used purely for the label.
select
    a.seller_id,
    s.seller_name,
    a.payout_count,
    a.paid_payout_count,
    a.paid_amount,
    a.line_count
from seller_agg a
left join sellers s
    on a.seller_id = s.seller_id
