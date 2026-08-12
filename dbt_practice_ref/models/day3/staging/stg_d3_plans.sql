-- Materialization: inherited from dbt_project.yml (day3: +materialized: view). No
-- in-model config needed — this model already lands on the required view.

select
    cast(PLAN_CODE as varchar)               as plan_code,
    cast(PLAN_NAME as varchar)               as plan_name,
    cast(TIER as varchar)                    as tier,
    cast(MONTHLY_PRICE_USD as decimal(10,2)) as monthly_price_usd

from {{ ref('raw_d3_plans') }}
