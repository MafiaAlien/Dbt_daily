-- V9: both directions in one test. A full outer join makes a missing mart row visible
-- (m.order_id is null) instead of silently comparing against NULL.
with stg as (

    select order_id, order_amount_usd
    from {{ ref('stg_d7_orders') }}

),

mart as (

    select
        order_id,
        count(*)              as mart_rows,
        min(order_amount_usd) as min_amount,
        max(order_amount_usd) as max_amount
    from {{ ref('fct_d7_orders_attributed') }}
    group by order_id

)

select
    coalesce(s.order_id, m.order_id) as order_id,
    case
        when s.order_id is null then 'in_mart_not_in_staging'
        when m.order_id is null then 'in_staging_not_in_mart'
        when m.mart_rows <> 1   then 'duplicated_in_mart'
        else 'amount_mismatch'
    end                              as failure,
    s.order_amount_usd               as staging_amount,
    m.min_amount,
    m.max_amount,
    m.mart_rows
from stg as s
full outer join mart as m
    on s.order_id = m.order_id
where s.order_id is null
   or m.order_id is null
   or m.mart_rows <> 1
   or m.min_amount is distinct from s.order_amount_usd
   or m.max_amount is distinct from s.order_amount_usd
