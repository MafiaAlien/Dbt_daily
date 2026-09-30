-- V10 

select 
    order_id 
from 
    {{ ref('fct_d7_orders_attributed')}} fct join {{ ref('snap_d7_accounts')}} snap
    on fct.account_id = snap.account_id
where fct.tier_at_order = 'UNKNOWN' and (fct.order_ts >= snap.dbt_valid_from and fct.order_ts < snap.dbt_valid_to)