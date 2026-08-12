{{
    config(
        materialized='view'
    )
}}

with src as (
    select 
        *
    from 
        {{ ref('raw_d3_plans') }}
),

renamed as (
    select 
        cast(PLAN_CODE as varchar) as plan_code,
        cast(PLAN_NAME as varchar) as plan_name,
        cast(TIER as varchar) as tier ,
        cast(MONTHLY_PRICE_USD as decimal(10, 2)) as monthly_price_usd
    from 
        src
)

select * from renamed