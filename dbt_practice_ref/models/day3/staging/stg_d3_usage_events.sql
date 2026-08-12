-- Materialization: inherited view from the day3: block.

select
    cast(EVENT_ID as varchar)        as event_id,
    cast(SUBSCRIPTION_ID as varchar) as subscription_id,
    cast(EVENT_DATE as date)         as event_date,
    cast(METRIC as varchar)          as metric,
    cast(UNITS as integer)           as units,
    cast(IS_BILLABLE as boolean)     as is_billable

from {{ ref('raw_d3_usage_events') }}
