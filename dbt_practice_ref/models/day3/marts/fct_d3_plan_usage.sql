-- Materialization: inherited table from the marts: sub-block. No in-model config needed.

with subscriptions as (

    select * from {{ ref('stg_d3_subscriptions') }}

),

billable_usage as (

    select * from {{ ref('int_d3_billable_usage') }}

),

subscriptions_by_plan as (

    select
        plan_code,
        count(*)                                            as subscription_count,
        count(case when status = 'active' then 1 end)       as active_subscription_count
    from subscriptions
    group by plan_code

),

usage_by_plan as (

    select
        plan_code,
        count(event_id)             as billable_event_count,
        sum(coalesce(units, 0))     as billable_units
    from billable_usage
    group by plan_code

)

select
    subscriptions_by_plan.plan_code,
    subscriptions_by_plan.subscription_count,
    subscriptions_by_plan.active_subscription_count,
    coalesce(usage_by_plan.billable_event_count, 0)          as billable_event_count,
    cast(coalesce(usage_by_plan.billable_units, 0) as integer) as billable_units

from subscriptions_by_plan
left join usage_by_plan
    on usage_by_plan.plan_code = subscriptions_by_plan.plan_code
