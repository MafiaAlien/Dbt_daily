--  V5  Every `account_id` in the snapshot has **exactly one** row with `dbt_valid_to is null`. Not at most one — exactly one.
select 
    account_id,
    dbt_valid_from
from 
    {{ ref('snap_d7_accounts') }}
group by    
    account_id,
    dbt_valid_from
having count(*) > 1