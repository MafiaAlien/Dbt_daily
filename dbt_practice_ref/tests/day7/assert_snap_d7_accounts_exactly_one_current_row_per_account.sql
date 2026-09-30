-- V5: every account_id has EXACTLY one open row (dbt_valid_to is null) — zero is a failure too.
select
    account_id,
    sum(case when dbt_valid_to is null then 1 else 0 end) as open_rows
from {{ ref('snap_d7_accounts') }}
group by account_id
having sum(case when dbt_valid_to is null then 1 else 0 end) <> 1
