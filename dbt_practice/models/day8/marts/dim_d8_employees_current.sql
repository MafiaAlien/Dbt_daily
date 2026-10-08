select 
    employee_id,
    full_name,
    department_code,
    job_title,
    salary_band,
    last_login_at,
    dbt_valid_from as current_since
from {{ ref('snap_d8_employees') }}
where dbt_valid_to is null 