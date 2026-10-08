-- V4 exactly once check
select 
    employee_id
from 
    {{ ref('snap_d8_employees')}}
where dbt_valid_to is null
group by employee_id
having count(*) > 1