{{
    config(
        materialized='view'
    )
}}

with src as (
    select 
        * 
    from {{ ref('raw_d3_subscriptions') }}
),

renamed as (
    select 
        cast(SUBSCRIPTION_ID as varchar) as subscription_id,
        cast(ACCOUNT_ID as varchar) as account_id,
        cast(PLAN_CODE as varchar) as plan_code,
        cast(STATUS as varchar) as status,
        cast(STARTED_ON as date) as started_on
    from 
        src 
)

select * from renamed