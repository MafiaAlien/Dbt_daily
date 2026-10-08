-- V4: every employee_id has exactly one row with dbt_valid_to is null (terminated ones included)
select
    employee_id,
    count(case when dbt_valid_to is null then 1 end) as open_rows
from {{ ref('snap_d8_employees') }}
group by employee_id
having count(case when dbt_valid_to is null then 1 end) <> 1
