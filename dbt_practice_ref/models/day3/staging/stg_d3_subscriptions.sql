-- Materialization: inherited view from the day3: block.

select
    cast(SUBSCRIPTION_ID as varchar) as subscription_id,
    cast(ACCOUNT_ID as varchar)      as account_id,
    cast(PLAN_CODE as varchar)       as plan_code,
    cast(STATUS as varchar)          as status,
    cast(STARTED_ON as date)         as started_on

from {{ ref('raw_d3_subscriptions') }}
