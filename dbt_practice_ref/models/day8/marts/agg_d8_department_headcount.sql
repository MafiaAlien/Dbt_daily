{{ config(materialized='table') }}

with departments as (

    select
        department_code,
        department_name
    from {{ ref('stg_d8_departments') }}

),

headcount as (

    select
        department_code,
        count(*) as n
    from {{ ref('dim_d8_employees_current') }}
    group by department_code

),

terminations as (

    -- department on the termination record = department at the moment of termination
    select
        department_code,
        count(*) as n
    from {{ ref('int_d8_employee_history') }}
    where is_deleted = true
    group by department_code

)

select
    dep.department_code,
    dep.department_name,
    cast(coalesce(h.n, 0) as integer) as current_headcount,
    cast(coalesce(t.n, 0) as integer) as terminations_to_date
from departments as dep
left join headcount as h
    on h.department_code = dep.department_code
left join terminations as t
    on t.department_code = dep.department_code
