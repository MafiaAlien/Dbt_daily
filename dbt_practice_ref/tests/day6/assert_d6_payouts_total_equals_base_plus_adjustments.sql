-- V8: the published total is internally consistent, exactly.

select
    delivery_date,
    city_code,
    payout_base_usd,
    adjustment_total_usd,
    total_payout_usd
from {{ ref('fct_d6_daily_city_payouts') }}
where total_payout_usd <> payout_base_usd + adjustment_total_usd
