-- V9: the int's plan_code equals the plan of the customer's version with the greatest
-- dbt_valid_from not after invoiced_at. Derived without dbt_valid_to, so it cannot inherit
-- the model's window predicate. Invoice facts come from staging, not from the int.
with invoices as (

    select
        invoice_id,
        customer_id,
        invoiced_at
    from {{ ref('stg_d9_invoices') }}

),

versions as (

    select
        customer_id,
        plan_code,
        dbt_valid_from
    from {{ ref('snap_d9_customers') }}

),

ranked as (

    select
        i.invoice_id,
        v.plan_code,
        row_number() over (
            partition by i.invoice_id
            order by v.dbt_valid_from desc
        ) as recency
    from invoices as i
    inner join versions as v
        on  v.customer_id = i.customer_id
        and v.dbt_valid_from <= i.invoiced_at

),

expected as (

    select
        invoice_id,
        plan_code as expected_plan_code
    from ranked
    where recency = 1

),

attributed as (

    select
        invoice_id,
        plan_code as model_plan_code
    from {{ ref('int_d9_invoice_revenue') }}

)

select
    a.invoice_id,
    a.model_plan_code,
    e.expected_plan_code
from attributed as a
left join expected as e
    on e.invoice_id = a.invoice_id
where e.expected_plan_code is null
   or a.model_plan_code is distinct from e.expected_plan_code
