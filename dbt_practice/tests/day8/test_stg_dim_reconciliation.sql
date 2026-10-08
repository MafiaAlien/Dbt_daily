-- V10
with stg as (
    select  
        employee_id as stg_emp
    from    
        {{ ref('stg_d8_employees') }}
),

dim as (
    select 
        employee_id as dim_emp,
        count(*) as cnt
    from 
        {{ ref('dim_d8_employees_current')}}
    group by employee_id
)

select 
    coalesce(stg_emp, dim_emp) as employee_id,
    case 
        when stg_emp is null then 'in mart not in stg'
        when dim_emp is null then 'in stg not in mart'
        when cnt <> 1 then 'dup in mart'
        end  as failure_flag
from 
    stg full outer join dim on stg.stg_emp = dim.dim_emp
where stg_emp is null or dim_emp is null or cnt <> 1