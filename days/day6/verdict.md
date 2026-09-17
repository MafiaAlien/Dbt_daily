# Day 6 — Verdict

Written before any execution.

## Notes while reading

- I ignored to add schema file for int, this is a good habit for any models with their corresponding schame config yaml file

## Material differences

- description for both stging models: I think this is not mandatory for documentation, but it better have;(equivalent)
- ref select courier_id but I did not select in int model, but courier_id is not relevant to final aggregation, extra selection will add more noises for final calculation;(mine)
- I did not cast payout_base_usd in int model because this did not do any manipulation of this step, it is redundant part I believe;(mine)
- I did not create schema yaml file for int model because preliminary quality checks had done in stg model; adding schema yaml here will be more rigorous for data quality check from some col which did manipulation here such as status and adjustments total usd;(reference)
- I added row number to dedup same delivery id with most recent "loaded_at", but references did not ,  I am not sure whether the final aggregation will be influenced by this, but I prefer my dedup here(mine)
- I use max date - interval 4 days and references use - 4 days directly(equivalent)
- references use sum but I used count to calculate completed count (equivalent )
- for V5, I also checked null for delivery cnt, but it is redundant because generic test already did it(references)
- for V7, references's answer is more rigorous than mine(references)
- for V8, I am not sure if I overthink this part, because I get data from staging model to validate if total_payout_usd is from sum of sub col(equivalent ) 

## My own solution — where I think it is wrong

- the first thing i want to mention in this part is I forgot to add schema config for int model, which bypass data quality checks in this step
- For V7 and V8 i am not sure if I was wrong or correct, especially V7, need to figure out

## Overall

- **Would ship:** reference — because references setup whole configs for int, and its models logic is same as mine, I prefer references' answer just because it has int schema config
- **Reference bugs I claim:**  None 
- **Could not settle by reading:** None
