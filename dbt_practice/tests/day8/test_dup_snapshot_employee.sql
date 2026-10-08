-- V7

select 
    a.employee_id
from 
    {{ ref('snap_d8_employees') }} a join {{ ref('snap_d8_employees') }} b on a.employee_id = b.employee_id 
where 
    a.dbt_valid_from = b.dbt_valid_to 
    and ((a.dbt_is_deleted = true or b.dbt_is_deleted = true)
    or (a.department_code = b.department_code and a.job_title = b.job_title and a.salary_band = b.salary_band))