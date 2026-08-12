{{ config(materialized = 'view') }}

-- The marts: sub-block would make this a table. dbt_project.yml is off-limits and a
-- per-model override in YAML would still be a project-file edit, so it goes here.

select
    plan_code,
    plan_name,
    tier,
    monthly_price_usd,
    monthly_price_usd is null as is_custom_priced

from {{ ref('stg_d3_plans') }}
