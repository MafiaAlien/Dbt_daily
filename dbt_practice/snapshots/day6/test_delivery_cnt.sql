-- V5
select 
    *
from 
    {{ ref('fct_d6_daily_city_payouts') }}
where delivery_count <= 0 OR delivery_count IS NULL