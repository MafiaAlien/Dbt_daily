{{ config(materialized='view') }}

with source as (

    select
        EMPLOYEE_ID,
        FULL_NAME,
        DEPARTMENT_CODE,
        JOB_TITLE,
        SALARY_BAND,
        RECORD_UPDATED_AT,
        LAST_LOGIN_AT,
        BATCH_ID
    from {{ ref('raw_d8_employee_dump') }}

),

renamed as (

    select
        cast(EMPLOYEE_ID       as varchar)   as employee_id,
        cast(FULL_NAME         as varchar)   as full_name,
        cast(DEPARTMENT_CODE   as varchar)   as department_code,
        cast(JOB_TITLE         as varchar)   as job_title,
        cast(SALARY_BAND       as varchar)   as salary_band,
        cast(RECORD_UPDATED_AT as timestamp) as record_updated_at,
        cast(LAST_LOGIN_AT     as timestamp) as last_login_at,
        cast(BATCH_ID          as integer)   as batch_id
    from source

)

select
    employee_id,
    full_name,
    department_code,
    job_title,
    salary_band,
    record_updated_at,
    last_login_at
from renamed
where batch_id = {{ var('d8_batch', 1) }}
