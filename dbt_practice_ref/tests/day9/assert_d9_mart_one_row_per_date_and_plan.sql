-- V11: grain of the mart is (invoice_date, plan_code).
select
    invoice_date,
    plan_code,
    count(*) as row_count
from {{ ref('fct_d9_daily_plan_revenue') }}
group by invoice_date, plan_code
having count(*) > 1
