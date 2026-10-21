# Day 9 — Verdict

Written before any execution.

## Notes while reading

<!-- 3-5 bullets. Odd things that are NOT material differences. -->

- got one critical mistake here, I did not use snapshot model in fct model

## Material differences

<!-- One bullet per difference. This is the section that gets scored. -->
<!-- A "difference" includes anything the reference does that mine does not do at all. -->
<!-- Every bullet must name a call — reference / mine / equivalent — and say why: -->
<!-- mechanism, not taste, i.e. what input would make the losing version wrong. -->
<!-- Where execution can settle it, name the test or the row of Expected Output. -->

- for int model I select customer stg but not snapshot model without dbt valida from/to as well (reference)
- for SLA 4 calendar day, reference uses dateadd func but I use - interval '4 days' in duckdb (equivalent)
- for V6, I added dbt_valid_to in to row number rank, this test just needs check if dbt valid to is unique(reference)
- for V6, I did not test if next dbt valid from is unique for open window (reference)
- for V8 I missed filter condition: "where s.invoice_id is null or m.invoice_id is null or m.row_count <> 1" (reference)
- for V9, totally different from answer of references, I did not join stg invoices with snapshot customer to rank by greatest dbt_valid_from not after invoice_at(to get most recent plan code in snapshot), then comparing plan_code values with ones in int model(reference)

## My own solution — where I think it is wrong

<!-- Mandatory. At least one honest entry, or an explicit statement of what you -->
<!-- re-checked and found clean. A bare "none" with no reasoning scores as a miss. -->

- snapshot model is not used in mart model
- V6 dbt_valid_to should not be used in window func and not test if valid_to is unique
- V8 lost where clause in full outer join(null and row_cnt is not equal to 1)
- V9 whole test logic is wrong

## Overall

- **Would ship:** reference — because reasons are listed in above part
- **Reference bugs I claim:** none
- **Could not settle by reading:** none
