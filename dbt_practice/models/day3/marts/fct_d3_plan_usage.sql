{{
    config(
        materialized='table'
    )
}}


with cnt as (
    select 
        s.plan_code,
        count(*) as subscription_count,
        sum(case when status = 'active' then 1 else 0 end) as active_subscription_count,
        sum(case when units is not null and is_billable is not null then units else 0 end) as billable_units
    from 
   {{ ref('stg_d3_subscriptions') }} s left join {{ ref('stg_d3_usage_events') }} e on s.subscription_id = e.subscription_id 
    group by s.plan_code
),

billable_cnt as (
    select 
        plan_code,
        count(*) as billable_event_count
    from {{ ref('int_d3_billable_usage') }}
    group by plan_code
)

select 
    c.plan_code,
    c.subscription_count,
    c.active_subscription_count,
    coalesce(b.billable_event_count, 0) as billable_event_count,
    c.billable_units
from  cnt c left join billable_cnt b on c.plan_code = b.plan_code
