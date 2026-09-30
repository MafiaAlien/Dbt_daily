{{ config(materialized='view') }}


with rk_most_updated as (
    select 
        *,
    row_number()over(partition by account_id order by updated_at desc) as _rn 
    from {{ ref('stg_d7_account_versions') }}
),

get_most_recent as (
    select 
        account_id,
        account_name,
        contract_tier,
        billing_region,
        account_status,
        updated_at
    from 
        rk_most_updated
    where _rn = 1  
)

select 
    *
from 
    get_most_recent