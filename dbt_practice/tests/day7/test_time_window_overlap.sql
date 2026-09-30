-- V6, time window validation, no overlapped part
with base as (
    select 
    * 
from 
    {{ ref('snap_d7_accounts') }} 
)    

select 
    * 
from 
    base a,
    base b 
where
    (a.dbt_valid_from < b.dbt_valid_from < a.dbt_valid_to) or (a.dbt_valid_from < b.dbt_valid_to < a.dbt_valid_to)