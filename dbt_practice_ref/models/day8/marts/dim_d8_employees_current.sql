{{ config(materialized='table') }}

with current_versions as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        dbt_valid_from
    from {{ ref('int_d8_employee_history') }}
    where is_current = true

),

todays_dump as (

    select
        employee_id,
        full_name,
        last_login_at
    from {{ ref('stg_d8_employees') }}

)

select
    cast(v.employee_id     as varchar)   as employee_id,
    cast(d.full_name       as varchar)   as full_name,       -- overwrite column: today's value
    cast(v.department_code as varchar)   as department_code,
    cast(v.job_title       as varchar)   as job_title,
    cast(v.salary_band     as varchar)   as salary_band,
    cast(d.last_login_at   as timestamp) as last_login_at,   -- overwrite column: today's value
    cast(v.dbt_valid_from  as timestamp) as current_since
from current_versions as v
left join todays_dump as d
    on d.employee_id = v.employee_id
