-- V6: completed deliveries are a subset of counted deliveries.

select
    delivery_date,
    city_code,
    delivery_count,
    completed_count
from {{ ref('fct_d6_daily_city_payouts') }}
where completed_count > delivery_count
