-- V4: no two mart rows share the same (delivery_date, city_code).

select
    delivery_date,
    city_code,
    count(*) as row_count
from {{ ref('fct_d6_daily_city_payouts') }}
group by delivery_date, city_code
having count(*) > 1
