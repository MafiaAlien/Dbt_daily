-- V12
with agg as (
    select 
        sum(current_headcount) as total_hc,
        sum(terminations_to_date) as total_terminations
    from 
        {{ ref('agg_d8_department_headcount')}}
),

cnt_stg as (
    select 
        count(*) as dim_cnt
    from 
        {{ ref('dim_d8_employees_current')}}
),

cnt_snap as (
    select 
        sum(case when dbt_is_deleted = true then 1 else 0 end) as cnt_termination
    from 
        {{ ref('snap_d8_employees')}}
)

select 
    case when total_hc <> dim_cnt then 'diff from headcount'
    end as flag
from 
    agg,
    cnt_stg
union all 
select 
    case when total_terminations <> cnt_termination then 'diff from termination'
    end as flag 
from 
    agg,
    cnt_snap