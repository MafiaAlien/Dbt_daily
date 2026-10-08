-- V6: both directions between the latest dump and the snapshot's open, non-termination rows.
with dump as (

    select employee_id, department_code, job_title, salary_band
    from {{ ref('stg_d8_employees') }}

),

open_versions as (

    select
        employee_id,
        department_code,
        job_title,
        salary_band,
        count(*) over (partition by employee_id) as open_versions_for_key
    from {{ ref('snap_d8_employees') }}
    where dbt_valid_to is null
      and dbt_is_deleted <> 'True'

),

compared as (

    select
        coalesce(d.employee_id, o.employee_id) as employee_id,
        case
            when o.employee_id is null
                then 'in dump, no open version in snapshot (missed insert/rehire)'
            when d.employee_id is null
                then 'open version for employee not in dump (missed termination)'
            when o.open_versions_for_key > 1
                then 'more than one open non-termination version'
            when d.department_code is distinct from o.department_code
              or d.job_title       is distinct from o.job_title
              or d.salary_band     is distinct from o.salary_band
                then 'tracked column differs from dump (missed change)'
        end as failure
    from dump as d
    full outer join open_versions as o
        on d.employee_id = o.employee_id

)

select employee_id, failure
from compared
where failure is not null
