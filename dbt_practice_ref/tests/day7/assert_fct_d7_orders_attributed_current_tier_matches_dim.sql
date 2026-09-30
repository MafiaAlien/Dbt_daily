-- V11: current_tier equals the dim's contract_tier when the account is in the dim,
-- and is 'UNKNOWN' exactly when it is not. Null-safe comparisons throughout, so a NULL
-- current_tier fails instead of slipping through a <> comparison.
select
    f.order_id,
    f.account_id,
    f.current_tier,
    d.contract_tier as dim_tier
from {{ ref('fct_d7_orders_attributed') }} as f
left join {{ ref('dim_d7_accounts_current') }} as d
    on d.account_id = f.account_id
where (d.account_id is null     and f.current_tier is distinct from 'UNKNOWN')
   or (d.account_id is not null and f.current_tier is distinct from d.contract_tier)
