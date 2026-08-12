{{
    config(
    materialized='view'
    )
}}

select 
    plan_code,
    plan_name,
    tier,
    monthly_price_usd,
    case when monthly_price_usd is null then true else false end as is_custom_priced
from 
    {{ ref('stg_d3_plans') }}