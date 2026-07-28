# Day 1 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets max. Anything odd that is not a material difference. -->

- `stg_d1_orders.sql` rename CTE — rename use a single CTE and cast data type, I need to learn this in ingestion
- `stg_d1_customers.sql` - same takeaways as above one
- `fct_d1_customer_orders` the agg_orders and final CTE - groupBy first and then use left join, so it calls two coaleces, but I am not sure if the performance is better than my solutions

## Overall

- **Would ship:** reference, because reference will be more precise than my version
- **Reference bugs I claim:** <list or "none"> None
- **Could not settle by reading:** <list> No