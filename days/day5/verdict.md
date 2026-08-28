# Day 5 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- references puts "not cancelled filter" and "row number tie breaker" in int table, but my solution just put 'non-cancelled' in int table and do tie break in fct table
- references puts table joint(most recent updated shipment left join shipment item table) in int table ,and I put this part in final fct table
- I bypass schema yaml file for int table
- I did not use is_incremental() in fct table, which lead to a wrong fan-out calculation in fact table(should leave calculation of item quantity and total weight in int table, then do final agg in fct table with incremental)
- I missed "shipment count is null" test in singular test part (V4)
- notes md is not completed 

## Material differences

<!-- One bullet per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->
<!-- Every bullet must name a call — reference / mine / equivalent — and say why: -->
<!-- mechanism, not taste, i.e. what input would make the losing version wrong. -->
<!-- Where execution can settle it, name the test or the row of Expected Output. -->

- not cancelled and updated-at tie breaker in int table in references, but I added update-at in fct table, which will affect is_incremental() method in final fct table that I missed (call: references)
- reference join tables in int stage, and I joined table in mart, which is not correct, the reason is same as above differences(call references)
- I did not wrote schema, because I config it as ephemeral model, however, it should be view because it contains critical logic for fan-out, non-cancel filter and update-at tie breaker.(call references)
- Reference use is_incremental() , but I bypass this part(because this is my first time to use is_incremental(), so I did not familiar with this dbt syntax, this is the reason I got wrong here); (call: references )
- Reference added "shipment count is null" test here, I just test shipment count is >= 1 (call: references)

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- the most critical wrong I got is that bypassing is_incremental() in fct table

## Overall

- **Would ship:** reference — because my solution has critical wrong on incrementals
- **Reference bugs I claim:** None
- **Could not settle by reading:** None
