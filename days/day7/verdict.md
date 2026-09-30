# Day 7 — Verdict

Written before any execution.

## Notes while reading

- I added one CTE in int model 

## Material differences

- I use <> "CHURNED" but not = "ACTIVE" in where clause of model dim accounts currents.(equivalent)
- I did not cast tier_at_order, region_at_order and current_tier at end of fct (reference)
- I did not join snap with "dat_valid_to is null" in fact model,(reference)
- I did "at most 1" for V5 test (reference)
- I just checked if each SCD 2 has overlap  but not joining by just account id without time window , and bypass empty window here for V6 (reference)
- I got no idea if reference's V9 is correct here, I suppose reference and I are equivalent (equivalent )
- missing "dbt_valid_to is null" in V10 (reference)

## My own solution — where I think it is wrong

- missing on filter condition "dat_valid_to is null" when joining fct model, the joining condition may not work by 3 values comparing(NULL compare a value)
- missing time window by row_number and empty window for V6, misunderstood requirements of verification

## Overall

- **Would ship:** reference  — because I have several lethal mistakes for test parts, especially V6
- **Reference bugs I claim:** None
- **Could not settle by reading:** None
