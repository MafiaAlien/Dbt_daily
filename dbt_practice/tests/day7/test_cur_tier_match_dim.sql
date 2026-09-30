-- V11 
select 
    account_id 
from    
    {{ref('fct_d7_orders_attributed')}} f left join {{ref('dim_d7_accounts_current')}} d 
    on f.account_id = d.account_id and f.order_ts >= d.current_since
where (d.contract_tier is not null and (f.tier_at_order = 'UNKNOWN' or (d.contract_tier <> f.tier_at_order)))
    or (d.contract_tier is null and f.tier_at_order <> 'UNKNOWN')
