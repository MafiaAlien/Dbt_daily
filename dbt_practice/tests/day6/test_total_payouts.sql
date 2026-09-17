-- V8
-- using payout_base usd and adj amout in raw table to check each delivery date & code in fct table

with sum_adj as (
    select 
        delivery_id,
        sum(adj_amount_usd) as total_adj_per_delivery
    from 
        {{ ref('stg_d6_delivery_adjustments') }}
    group by delivery_id
),

sum_delivery as (
    select 
        delivery_date,
        city_code,
        delivery_id,
        sum(payout_base_usd) as total_payouts
    from 
        {{ ref('stg_d6_deliveries') }}
    where status <> 'CANCELLED'
    group by delivery_date, city_code, delivery_id
),

agg_raw as (
    select 
        delivery_date,
        city_code,
        sum(total_payouts) + coalesce(sum(total_adj_per_delivery),0) as raw_total
    from 
        sum_delivery sd left join sum_adj sa on sa.delivery_id = sd.delivery_id
    group by delivery_date, city_code
)

select
    *
from 
    agg_raw ar,
    {{ ref('fct_d6_daily_city_payouts') }} fct 
where ar.raw_total <> fct.total_payout_usd