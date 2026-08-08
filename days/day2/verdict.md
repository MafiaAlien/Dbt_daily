# Day 2 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- reference's source yaml is same as mine
- reference implement cast at most inner place of order_status, but I used it at most external
- reference implement row_number in another cte statement and filter in final query, but I did row number rank in renamed cte
- reference implement coalesce for NULL region and use another cte statement to calculate completed order 
## Material differences

<!-- One block per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->

### D1 — <one-line title>

- **Reference does:**cast order_status inside trim and lower func
- **I did:** trim and lower order_status then cast outside of them
- **Call:** reference 
- **Why:** <mechanism, not taste. What input would make the losing version wrong?>: reference's solution will ensure the trim and lower to implement on string
- **How execution would settle it:** <which test, or which row of Expected Output>: no clue

### D2 — <one-line title>

- **Reference does:**use row_number to rank exported_at in another cte
- **I did:** use row_number in renamed cte and filter in final query
- **Call:** equivalent
- **Why:** no clue
- **How execution would settle it:** no clue

### D3 — <one-line title>

- **Reference does:** coalesce unmapped region by exclusive cte
- **I did:** coalesce unmmaped region in aggregation steps
- **Call:** equivalent
- **Why:** no clue
- **How execution would settle it:** no clue

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- I should split some cast step by specific step to ensure following steps has correct format to do manupulation and rank

## Overall

- **Would ship:** reference — because it specified steps to implement null region, and row_number rank, which is more intuitive on reading
- **Reference bugs I claim:** <list or "none"> None
- **Could not settle by reading:** <list or "none"> None
