-- V10: no row is UNKNOWN while a snapshot version covering its order_ts exists.
-- Uses the reference definition of "in effect": [dbt_valid_from, dbt_valid_to), NULL = open.
select
    f.order_id,
    f.account_id,
    f.order_ts,
    s.contract_tier  as covering_tier,
    s.dbt_valid_from as covering_from,
    s.dbt_valid_to   as covering_to
from {{ ref('fct_d7_orders_attributed') }} as f
join {{ ref('snap_d7_accounts') }} as s
    on  s.account_id = f.account_id
    and f.order_ts >= s.dbt_valid_from
    and (s.dbt_valid_to is null or f.order_ts < s.dbt_valid_to)
where f.tier_at_order = 'UNKNOWN'
