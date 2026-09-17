# Day 6 — notes

## Grain plan

| Column | Grain it is computed at | Aggregation | Filter | Comes from |
|---|---|---|---|---|
| Delivery_count | One delivery | Count | Status <> cancelled | int_d6_not_cancelled_latest |
| Completed_count | one delivery | Count | Status <> cancelled | int_d6_not_cancelled_latest |
| payout_base_usd | one delivery | Sum | Status <> cancelled | int_d6_not_cancelled_latest |
| adjustment_total_usd | one delivery | Sum | Status <> cancelled | int_d6_not_cancelled_latest |
| total_payout_usd | one delivery | Sum | Status <> cancelled | int_d6_not_cancelled_latest |

Row matching between the two source models — one sentence each:

## Watermark plan

1. Watermark date at the start of run 3:

   

2. Oldest `delivery_date` batch 3 may legally contain (derived from the SLA and the
   batch-3 load timestamp):

3. Gap in days, and what the incremental filter must therefore do:

## Assumptions
### create an int model to do intermediate aggregation for following incremental model in mart 
1. filter out any cancelled delivery in 1st step
2. do aggregation in delivery adj table, joining with stg delivery table by delivery_id to prepare final aggregation in fct table

## Config decisions

config marterialized view for stg and int tables, incremental for mart table

## Run log

## Debrief answers
