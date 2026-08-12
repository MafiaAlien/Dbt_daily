{{
    config(
        materialized='view'
    )
}}

with src as (
    select 
        *
    from 
        {{ ref('raw_d3_usage_events') }}
),

renamed as (
    select 
        cast(EVENT_ID as varchar) as event_id,
        cast(SUBSCRIPTION_ID as varchar) as subscription_id,
        cast(EVENT_DATE as date) as event_date,
        cast(METRIC as varchar) as metric,
        cast(UNITS as integer) as units,
        cast(IS_BILLABLE as boolean) as is_billable
    from 
        src 

)
select * from renamed
