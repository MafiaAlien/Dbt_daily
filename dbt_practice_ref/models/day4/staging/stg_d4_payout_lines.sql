{{ config(materialized='view') }}

-- Rename and cast only. NULLs from the faulty May export pass through untouched:
-- L010 (orphan payout_id), L011 (null payout_id), L012 (null currency) all reach this view.
select
    cast(LINE_ID        as varchar)       as line_id,
    cast(PAYOUT_ID      as varchar)       as payout_id,
    cast(ORDER_REF      as varchar)       as order_ref,
    cast(CURRENCY       as varchar)       as currency,
    cast(LINE_AMOUNT    as decimal(12,2)) as line_amount,
    cast(PAYMENT_METHOD as varchar)       as payment_method
from {{ ref('raw_d4_payout_lines') }}
