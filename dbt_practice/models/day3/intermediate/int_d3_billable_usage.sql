{{
    config(
        materialized='ephemeral'
    )
}}

select 
    e.event_id,
    e.subscription_id,
    s.plan_code,
    e.event_date,
    e.units
from {{ ref('stg_d3_usage_events') }} e join {{ ref('stg_d3_subscriptions') }} s on e.subscription_id = s.subscription_id
where s.status = 'active' and e.is_billable is true 