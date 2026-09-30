select 
    account_id,
    account_name,
    contract_tier,
    billing_region,
    dbt_valid_from as current_since
from 
     {{ ref('snap_d7_accounts') }}
 where account_status <> 'CHURNED' and dbt_valid_to is null
 