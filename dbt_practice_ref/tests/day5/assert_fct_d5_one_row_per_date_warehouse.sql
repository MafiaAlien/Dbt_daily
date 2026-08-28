-- V4: the declared grain. Fails if any (ship_date, warehouse_code) repeats.
select
    ship_date,
    warehouse_code,
    count(*) as row_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
group by ship_date, warehouse_code
having count(*) > 1
