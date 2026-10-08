-- V7: consecutive non-termination versions of one employee must differ in a tracked column.
with versions as (

    select employee_id, department_code, job_title, salary_band,
           dbt_valid_from, dbt_valid_to, dbt_is_deleted
    from {{ ref('snap_d8_employees') }}

)

select
    a.employee_id,
    a.dbt_valid_from as earlier_from,
    b.dbt_valid_from as later_from
from versions as a
join versions as b
    on  a.employee_id  = b.employee_id
    and a.dbt_valid_to = b.dbt_valid_from
where a.dbt_is_deleted <> 'True'
  and b.dbt_is_deleted <> 'True'
  and a.department_code is not distinct from b.department_code
  and a.job_title       is not distinct from b.job_title
  and a.salary_band     is not distinct from b.salary_band
