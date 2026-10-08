/*
V7
For every (`delivery_date`, `city_code`) that has at least one non-cancelled delivery
in `stg_d6_deliveries`, the mart has exactly one row, and that row's `delivery_count`
equals the number of such deliveries. The mart has no row for any 
(`delivery_date`, `city_code`) that has none.
*/

with cnt_stg as (
    select 
        delivery_date,
        city_code,
        count(*) as stg_cnt
    from 
        {{ ref('stg_d6_deliveries')}}
    where status <> 'CANCELLED'
    group by 
        delivery_date,
        city_code
)

select 
    *
from cnt_stg left join {{ ref('fct_d6_daily_city_payouts') }} fct 
on (fct.delivery_date = cnt_stg.delivery_date and fct.city_code = cnt_stg.city_code) 
where 
    stg_cnt <> delivery_count