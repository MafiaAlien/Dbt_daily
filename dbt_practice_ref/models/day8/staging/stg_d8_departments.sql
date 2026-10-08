{{ config(materialized='view') }}

with source as (

    select
        DEPARTMENT_CODE,
        DEPARTMENT_NAME
    from {{ ref('raw_d8_departments') }}

),

renamed as (

    select
        cast(DEPARTMENT_CODE as varchar) as department_code,
        cast(DEPARTMENT_NAME as varchar) as department_name
    from source

)

select
    department_code,
    department_name
from renamed
