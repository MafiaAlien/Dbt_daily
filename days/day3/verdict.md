# Day 3 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- in staging and intermediate, the logics of AI's solutions and mina are almost same, but a little differences happen in mart level, which AI count billable values from intermedia table but I just get billable event count from intermedia level

## Material differences

<!-- One block per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->

### D1 — <int_d3_billable> 

- **Reference does:** int_d3_billable_usage.sql just use "where usage_events.is_billable
  and subscriptions.status = 'active'" 
- **I did:** I use "is_billable is true 
- **Call:** reference / mine / equivalent: equivalent
- **Why:** <mechanism, not taste. What input would make the losing version wrong?> I think both are ok
- **How execution would settle it:** <which test, or which row of Expected Output> I am not sure if my code will be more clear for some test 

### D2 — <fct_d3_plan_usage>

- **Reference does:** AI count billable event sourcing from intermediate level
- **I did:** I re-count billable event count from original event table
- **Call:** quivalent
- **Why:** I think my solution will lose because I add one more "is_billable = True" in query of mart, which will lead to raise possbilities of error 
- **How execution would settle it:** no idear

### D3 — <stg_d3_plans, stg_d3_subscriptions, stg_d3_usage_events, fct_d3_plan_usage, >

- **Reference does:** AI skip the definition of materialized config in model
- **I did:** I set strategy of materialized in config no matter how they are set in dbt project yaml
- **Call:** mine
- **Why:** mine solution will be more robust and clear if other people review the model code 
- **How execution would settle it:** if some one change materialized config in dbt yaml, the AI's models will be affected 

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- as I mentioned above: for the mart level, I count billable event from original table;

## Overall

- **Would ship:** reference / mine — because I will ship neither, because AI does not define config, and I have fault on mart level of fct_d3_plan_usage model
- **Reference bugs I claim:** <list or "none"> None
- **Could not settle by reading:** <list or "none"> None
