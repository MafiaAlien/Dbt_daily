with src as (
    select 
        * 
    from 
        {{ ref('raw_d8_employee_dump') }}
),

renamed as (

select 
    cast(EMPLOYEE_ID as varchar) as employee_id,
    cast(FULL_NAME as varchar) as full_name,
    cast(DEPARTMENT_CODE as varchar) as department_code,
    cast(JOB_TITLE as varchar) as job_title,
    cast(SALARY_BAND as varchar) as salary_band,
    cast(RECORD_UPDATED_AT as  timestamp) as record_updated_at,
    cast(LAST_LOGIN_AT as timestamp) as last_login_at 
from src 
where BATCH_ID = {{ var('d8_batch', 1) }}
)

select * from renamed