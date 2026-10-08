{{ config(materialized='view') }}

with snapshot_rows as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        dbt_valid_from,
        dbt_valid_to,
        dbt_is_deleted
    from {{ ref('snap_d8_employees') }}

)

select
    cast(employee_id     as varchar)   as employee_id,
    cast(department_code as varchar)   as department_code,
    cast(job_title       as varchar)   as job_title,
    cast(salary_band     as varchar)   as salary_band,
    cast(dbt_valid_from  as timestamp) as dbt_valid_from,
    cast(dbt_valid_to    as timestamp) as dbt_valid_to,
    -- dbt writes the flag as the strings 'True' / 'False'
    case when dbt_is_deleted = 'True' then true else false end as is_deleted,
    -- open window (dbt_valid_to_current at default => NULL) and not a termination record
    case
        when dbt_valid_to is null and dbt_is_deleted <> 'True' then true
        else false
    end as is_current
from snapshot_rows
