-- V10: every stg employee appears in the dim exactly once; the dim has nobody not in stg.
with stg as (

    select employee_id
    from {{ ref('stg_d8_employees') }}

),

dim as (

    select employee_id, count(*) as dim_rows
    from {{ ref('dim_d8_employees_current') }}
    group by employee_id

),

compared as (

    select
        coalesce(s.employee_id, d.employee_id) as employee_id,
        case
            when d.employee_id is null then 'in stg_d8_employees, missing from dim'
            when s.employee_id is null then 'in dim, not in stg_d8_employees'
            when d.dim_rows > 1        then 'duplicated in dim'
        end as failure
    from stg as s
    full outer join dim as d
        on s.employee_id = d.employee_id

)

select employee_id, failure
from compared
where failure is not null
