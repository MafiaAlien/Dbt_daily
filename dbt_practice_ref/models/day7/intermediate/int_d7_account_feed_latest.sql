-- No config on purpose: no dbt_project.yml entry for this folder, so dbt's default (view) applies.
-- Grain: one row per account_id, the latest version visible to the current batch.
-- This is the snapshot's relation; a snapshot must see exactly one row per unique_key.
with ranked as (

    select
        account_id,
        account_name,
        contract_tier,
        billing_region,
        account_status,
        updated_at,
        row_number() over (
            partition by account_id
            order by updated_at desc
        ) as version_rank
    from {{ ref('stg_d7_account_versions') }}

)

select
    account_id,
    account_name,
    contract_tier,
    billing_region,
    account_status,
    updated_at
from ranked
where version_rank = 1
