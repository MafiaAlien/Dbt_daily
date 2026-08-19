# Day 4 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->
- set conig in model but not in dbt project yaml 
- AI documents some columns those do not need test in yaml(such as order_ref, seller_name in fct table)
- more detailed description for each column

## Material differences

<!-- One block per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->

- I ignore test for C15 and C16 (call references)
- I use a custom generic test to cover all not_negative validation (call references)
- AI casts paymount_amount to decimal during aggregation (call references)
- my custome generic test compile failed

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- bypass the tests for C15 and C16
- ignore cast payout_amount during agg

## Overall

- **Would ship:** reference  — because 
    - tests includes C15 and C16, which will be more robust 
- **Reference bugs I claim:** 
    - None
- **Could not settle by reading:**  None
