-- V5: every published row represents at least one delivery.

select
    delivery_date,
    city_code,
    delivery_count
from {{ ref('fct_d6_daily_city_payouts') }}
where delivery_count < 1
