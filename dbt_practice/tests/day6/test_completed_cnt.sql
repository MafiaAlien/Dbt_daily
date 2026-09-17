-- V6
select 
    *
from 
    {{ ref('fct_d6_daily_city_payouts') }}
where completed_count > delivery_count