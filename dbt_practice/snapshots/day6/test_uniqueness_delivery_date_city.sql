-- V4
select 
    delivery_date, city_code 
from 
    {{ ref('fct_d6_daily_city_payouts') }}
group by
    delivery_date, city_code 
having 
    count(*) > 1