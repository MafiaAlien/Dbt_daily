-- V6: delivered shipments are a subset of counted shipments.
select
    ship_date,
    warehouse_code,
    shipment_count,
    delivered_count
from {{ ref('fct_d5_daily_warehouse_shipments') }}
where delivered_count > shipment_count
