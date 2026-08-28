select 
    delivered_count,
    shipment_count
from 
    {{ ref("fct_d5_daily_warehouse_shipments") }}
where delivered_count > shipment_count