{{ config(materialized='view') }}

with non_cancelled_deliveries as (
    select 
        delivery_date,
        city_code,
        delivery_id,
        status,
        payout_base_usd,
        row_number()over(partition by delivery_id order by loaded_at desc) as _rn
    from 
        {{ ref("stg_d6_deliveries") }}
    where 
        status <> 'CANCELLED'
),

total_adj_amounts as (
    select 
        delivery_id,
        sum(adj_amount_usd) as adjustment_total_usd 
    from    
        {{ ref("stg_d6_delivery_adjustments") }}
    group by delivery_id
),

tb_join_deliveries_adj as (
    select 
        delivery_date,
        city_code,
        status,
        payout_base_usd,
        cast(coalesce(adjustment_total_usd, 0) as decimal(10, 2)) as adjustment_total_usd
    from 
        non_cancelled_deliveries n left join total_adj_amounts taa on n.delivery_id = taa.delivery_id 
    where _rn = 1
)

select 
    * from tb_join_deliveries_adj