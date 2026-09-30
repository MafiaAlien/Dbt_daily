with src as (
    select 
        *
    from 
        {{ ref('raw_d7_account_versions') }}
),

renamed as (
    select 
        cast(ACCOUNT_ID as varchar) as account_id,
        cast(ACCOUNT_NAME as varchar) as account_name,
        cast(CONTRACT_TIER as varchar) as contract_tier,
        cast(BILLING_REGION as varchar) as billing_region,
        cast(ACCOUNT_STATUS as varchar) as account_status,
        cast(UPDATED_AT as timestamp) as updated_at
    from 
        src 
    where batch_id <= {{ var('d7_batch', 1) }}
)

select * from renamed 