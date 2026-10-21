 -- V6 exactly once for each dbt_valid_to of the customers


with windows as(
    select 
        customer_id,
        dbt_valid_from,
        dbt_valid_to,
        row_number()over(partition by customer_id order by dbt_valid_from, dbt_valid_to) as window_seq
     {{ ref('snap_d9_customers') }}
),

dup_open_customer as (
    select 
        customer_id,
        'dup_open_customer' as failure_flag,
        cast(null as timestamp) as window_a_from,
        cast(null as timestamp) as window_a_to,
        cast(null as timestamp) as window_b_from,
        cast(null as timestamp) as window_b_to
    from 
        windows
    where dbt_valid_to is null 
    group by customer_id
    having count(*) > 1
)

empty_window as (
    select 
    customer_id,
   'empty_window' as failure_flag,
    dbt_valid_from as window_a_from,
    dbt_valid_to as window_a_to,
    cast(null as timestamp) as window_b_from,
    cast(null as timestamp) as window_b_to
    from 
        windows
    where dbt_valid_to is not null and dbt_valid_to <= dbt_valid_from
)

overlapping_window as (
    select 
        customer_id,
        'overlap' as failure_flag,
        a.dbt_valid_from as window_a_from,
        a.dbt_valid_to as window_a_to,
        b.dbt_valid_from as window_b_from,
        b.dbt_valid_to as window_b_to 
    from 
        windows a join windows b on a.employee_id = b.employee_id and a.window_seq < b.window_seq
    where 
        (b.dbt_valid_to is null or a.dbt_valid_from < b.dbt_valid_to)
        and (a.dbt_valid_to is null or b.dbt_valid_from < a.dbt_valid_to)
)


select 
    *
from 
    dup_open_customer
union all 
select 
    *
from 
    empty_window
union all 
select 
    *
from 
    overlapping_window
