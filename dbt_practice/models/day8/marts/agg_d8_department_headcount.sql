with delete_cnt as (
    select 
        department_code,
        sum(case when is_deleted = true then 1 else 0 end) as terminations_to_date
    from 
        {{ ref('int_d8_employee_history') }}
    group by department_code
),

current_cnt as (
    select 
        department_code,
        count(employee_id) as current_headcount
    from {{ ref('dim_d8_employees_current') }}
    group by department_code
)


select 
    stg.department_code,
    stg.department_name,
    cast(coalesce(current_headcount, 0) as bigint) as current_headcount,
    cast(coalesce(terminations_to_date, 0) as bigint) as terminations_to_date
from 
    {{ ref('stg_d8_departments') }} stg left join delete_cnt  dc on stg.department_code = dc.department_code
    left join current_cnt cc on stg.department_code = cc.department_code



