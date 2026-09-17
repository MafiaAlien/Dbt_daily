{{
    config(
        materialized="incremental",
        unique_key=['delivery_date', 'city_code'],
        incremental_strategy="merge",
        on_schema_change="fail",
    )
}}

with latest_delivery as (
    select 
        *
    from 
        {{ ref('int_d6_not_cancelled_latest') }}
        {% if is_incremental() %}
            where delivery_date > (select coalesce(max(delivery_date), cast('1900-01-01' as date)) from {{ this }}) - interval '4' days
        {% endif %}
),

aggregation_cnt_payouts as (
    select 
        delivery_date,
        city_code,
        count(*) as delivery_count,
        count(case when status = 'COMPLETED' then 1 end) as completed_count,
        cast(sum(payout_base_usd) as decimal(10, 2)) as payout_base_usd,
        cast(sum(adjustment_total_usd) as decimal(10, 2)) as adjustment_total_usd
    from 
        latest_delivery
    group by delivery_date, city_code
)

select 
    delivery_date,
    city_code,
    cast(delivery_count as integer) as delivery_count,
    cast(completed_count as integer) as completed_count,
    payout_base_usd,
    adjustment_total_usd,
    cast((payout_base_usd + adjustment_total_usd) as decimal(10, 2)) as total_payout_usd
from 
    aggregation_cnt_payouts