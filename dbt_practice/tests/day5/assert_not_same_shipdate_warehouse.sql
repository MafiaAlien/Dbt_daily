select 
    concat(ship_date, warehouse_code) as combination
from 
{{ ref('fct_d5_daily_warehouse_shipments') }}
group by 
    concat(ship_date, warehouse_code)
having count(*) > 1
