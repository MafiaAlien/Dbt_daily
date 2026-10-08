-- V12: sum(current_headcount) = rows in dim; sum(terminations_to_date) = termination records in snapshot.
with agg_totals as (

    select
        coalesce(sum(current_headcount), 0)    as total_headcount,
        coalesce(sum(terminations_to_date), 0) as total_terminations
    from {{ ref('agg_d8_department_headcount') }}

),

dim_total as (

    select count(*) as dim_rows
    from {{ ref('dim_d8_employees_current') }}

),

snap_total as (

    select count(*) as termination_records
    from {{ ref('snap_d8_employees') }}
    where dbt_is_deleted = 'True'

)

select
    a.total_headcount,
    d.dim_rows,
    a.total_terminations,
    s.termination_records
from agg_totals as a
cross join dim_total as d
cross join snap_total as s
where a.total_headcount    <> d.dim_rows
   or a.total_terminations <> s.termination_records
