with 
orders as (
    select 
        * 
    from 
        {{ ref('stg_d2_orders') }}
),

country_region as (
    select 
        * 
    from
        {{ ref('stg_d2_country_region') }}
),

agg as (
    select 
        coalesce(cr.region, 'Unmapped') as region,
        count(*) as total_order_count,
        sum(case when o.order_status = 'completed' then 1 else 0 end) as completed_order_count,
        sum(case when o.order_status = 'completed' then coalesce(amount_usd, 0) else 0 end) as gross_revenue_usd
    from 
        orders o left join country_region cr using(country_code) 
    group by 
        coalesce(cr.region, 'Unmapped')
)

select 
    region,
    cast(total_order_count as integer) as total_order_count,
    cast(completed_order_count as integer) as completed_order_count,
    cast(gross_revenue_usd as decimal(12, 2)) as gross_revenue_usd

from 
    agg 