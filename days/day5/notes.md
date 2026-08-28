## Grain plan

| Column | Grain it is computed at | Aggregation | Filter | Comes from |  |
|---|---|---|---|---|---|
| Item_quantity | One shipment | Sum | not cancelled | Quantity |  |
| total_weight_kg | One shipment | Sum | not cancelled | line_weight_kg |  |
| shipment_count | (ship date, warehouse) | Count       | not cancelled | all rows in intermedia table: int_d5_filter_cancelled |  |
| delivered_count | (ship date, warehouse) | Count | not cancelled | rows with status "deliveried" |  |
| shipping_cost_usd | (ship date, warehouse) | Sum | not cancelled | total cost in this date |  |



## Assumptions

- 
## Config decisions

- int table uses ephemeral 
- fct table is incremental using on_schema_change='fail',

## Run log

## Debrief answers
