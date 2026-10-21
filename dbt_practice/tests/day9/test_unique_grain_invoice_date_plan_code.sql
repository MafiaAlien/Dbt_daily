-- V11 No two rows share (`invoice_date`, `plan_code`).

select 
    invoice_date,
    plan_code 
from 
    {{ ref('fct_d9_daily_plan_revenue')}}
group by invoice_date, plan_code
having count(*) > 1