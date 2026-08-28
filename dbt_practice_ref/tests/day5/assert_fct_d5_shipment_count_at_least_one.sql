-- V5: an all-cancelled (date, warehouse) must produce no row, never a zero row.
select
    ship_date,
    warehouse_code,
    shipment_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
where shipment_count is null
   or shipment_count < 1
