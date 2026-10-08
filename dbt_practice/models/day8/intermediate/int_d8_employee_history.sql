with src as (
    select 
        employee_id,
        department_code,
        job_title,
        salary_band,
        dbt_valid_from,
        dbt_valid_to,
        dbt_is_deleted as is_deleted,
        case when dbt_valid_to is null then true else false end as is_current
    from 
        {{ ref('snap_d8_employees') }}
)

select * from src 



