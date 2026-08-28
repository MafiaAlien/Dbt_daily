select 
    shipment_count
from 
{{ ref('fct_d5_daily_warehouse_shipments') }}
where shipment_count < 1