{{ config(materialized='view') }}

-- Rename and cast only. No filtering, dedup, repair or imputation.
select
    cast(PAYOUT_ID     as varchar)       as payout_id,
    cast(SELLER_ID     as varchar)       as seller_id,
    cast(PAYOUT_DATE   as date)          as payout_date,
    cast(STATUS        as varchar)       as status,
    cast(CURRENCY      as varchar)       as currency,
    cast(PAYOUT_AMOUNT as decimal(12,2)) as payout_amount
from {{ ref('raw_d4_payouts') }}
