with orders as (
    select 
        order_id,
        account_id,
        order_ts,
        order_amount_usd
    from 
        {{ ref('stg_d7_orders') }}
),

snap_accounts as (
    select 
        account_id,
        contract_tier,
        billing_region,
        dbt_valid_from,
        dbt_valid_to
    from 
        {{ ref('snap_d7_accounts')}}
),

cur_account as (
    select 
        account_id,
        contract_tier
    from 
        {{ ref('dim_d7_accounts_current') }}
)

select 
    o.order_id,
    o.account_id,
    o.order_ts
    o.order_amount_usd,
    coalesce(s.contract_tier, 'UNKNOWN') as tier_at_order,
    coalesce(s.billing_region, 'UNKNOWN') as region_at_order,
    coalesce(c.contract_tier, 'UNKNOWN') as current_tier
from 
    orders o left join snap_accounts s on o.account_id and s.dbt_valid_from <= o.order_ts < s.dbt_valid_to
    left join cur_account c on o.account_id = c.account_id