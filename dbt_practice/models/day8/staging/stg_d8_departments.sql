with src as (
    select 
        *
    from 
        {{ ref('raw_d8_departments') }}
),

renamed as (
    select 
        cast(DEPARTMENT_CODE as varchar) as department_code,
        cast(DEPARTMENT_NAME as varchar) as department_name
    from 
        src 
)

select * from renamed