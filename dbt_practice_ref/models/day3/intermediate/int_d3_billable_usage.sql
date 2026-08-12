{{ config(materialized = 'ephemeral') }}

-- The day3: block would make this a view. `intermediate` has no sub-block of its own and
-- dbt_project.yml is off-limits, so the override has to live in the model.

with usage_events as (

    select * from {{ ref('stg_d3_usage_events') }}

),

subscriptions as (

    select * from {{ ref('stg_d3_subscriptions') }}

)

select
    usage_events.event_id,
    usage_events.subscription_id,
    subscriptions.plan_code,
    usage_events.event_date,
    usage_events.units

from usage_events
inner join subscriptions
    on subscriptions.subscription_id = usage_events.subscription_id

where usage_events.is_billable
  and subscriptions.status = 'active'
