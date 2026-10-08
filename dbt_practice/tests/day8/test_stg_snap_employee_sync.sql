-- V6 
with stg as (
    select 
        employee_id,
        department_code,
        job_title,
        salary_band
    from 
        {{ ref('stg_d8_employees') }}
),

snap as (
    select 
        employee_id,
        department_code,
        job_title,
        salary_band
    from 
        {{ ref('snap_d8_employees') }}
    where dbt_is_deleted = false and dbt_valid_to is null 
)

-- employees in snap have same tracked cols with dump and exactly once 
select  
    g.employee_id as employee_id
from 
    stg g full outer join snap p on g.employee_id = p.employee_id 
where (g.department_code <> p.department_code) or (g.job_title <> p.job_title) or (g.salary_band <> p.salary_band)
or (g.employee_id is null) or (p.employee_id is null)
group by g.employee_id
having count(*) > 1