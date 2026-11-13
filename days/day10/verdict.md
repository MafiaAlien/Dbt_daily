# Day 10 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- no notes 

## Material differences

<!-- One bullet per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->
<!-- Every bullet must name a call — reference / mine / equivalent — and say why: -->
<!-- mechanism, not taste, i.e. what input would make the losing version wrong. -->
<!-- Where execution can settle it, name the test or the row of Expected Output. -->

- reference used inner join but I use left join in intermediate model(equivalent)
- I calculate order cnt directly from fct table but reference count from staging table in marts(equivalent)
- I got method and other cnt and sum of amount in single query with jinja for loop. reference use seperated ones(equivalent)


## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- no critical error for this practice i believe; but I should use inner join in intermediate model

## Overall

- **Would ship:** reference — because references will be more rigorious 
- **Reference bugs I claim: None
- **Could not settle by reading: None
