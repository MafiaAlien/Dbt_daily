# Day 8 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- listed in next part

## Material differences

<!-- One bullet per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->
<!-- Every bullet must name a call — reference / mine / equivalent — and say why: -->
<!-- mechanism, not taste, i.e. what input would make the losing version wrong. -->
<!-- Where execution can settle it, name the test or the row of Expected Output. -->

- dbt_is_deleted is string for reference(equivalent)
- case when true for is_deleted col against value of dbt_is_deleted(equivalent)
- reference add dbt_is_deleted <> True for case when condition of is_current col  (reference)
- reference add today's dump from stg_employees, then left join with int model(reference)
- for V5, reference uses "order by dbt_valid_from, dbt_valid_to nulls last" to handle null in dbt_valid_to (reference)
- reference uses "when d.department_code is distinct from o.department_code" to verify differences among these values but I used join to compare two values with same emp id (reference)
- reference's V7 same as V6, I did not use distinct to verify (reference), and I use wrong where cond "  "and (a.dbt_is_deleted = true or b.dbt_is_deleted = true)" in the test, which should be <> True

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- dbt_is_deleted return string True/False but bot boolean values
- misunderstand today'dump
- did not know "distinct" can be used to compare different values in two tables

## Overall

- **Would ship:** reference — because logic of mart model is wrong and a few tests(V5 V6, V7) are not correct as well
- **Reference bugs I claim:** none
- **Could not settle by reading:** the return value of dbt_is_deleted
