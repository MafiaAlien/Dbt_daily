-- Materialization: table (also set by the day7.marts block in dbt_project.yml)
{{ config(materialized='table') }}

-- Grain: one row per account whose CURRENT version is ACTIVE.
-- Both predicates apply to the same row: first "is the current version",
-- then "that current version is ACTIVE". A churned account's older ACTIVE
-- versions are closed (dbt_valid_to not null), so they can never qualify.
select
    account_id,
    account_name,
    contract_tier,
    billing_region,
    dbt_valid_from as current_since
from {{ ref('snap_d7_accounts') }}
where dbt_valid_to is null
  and account_status = 'ACTIVE'
