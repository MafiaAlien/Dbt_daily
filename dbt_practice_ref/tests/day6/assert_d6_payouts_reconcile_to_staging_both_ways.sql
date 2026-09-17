-- V7: the reconciliation, in both directions.
--   * every (delivery_date, city_code) with >= 1 non-cancelled delivery in
--     staging has exactly one mart row, with a matching delivery_count;
--   * the mart has no row for a pair with no such deliveries.
-- The FULL OUTER JOIN is what makes the second direction detectable: a row the
-- mart never wrote is invisible to any test that starts from the mart.

with expected as (

    select
        delivery_date,
        city_code,
        count(*) as delivery_count
    from {{ ref('stg_d6_deliveries') }}
    where status <> 'CANCELLED'
    group by delivery_date, city_code

),

actual as (

    select
        delivery_date,
        city_code,
        count(*)            as mart_row_count,
        max(delivery_count) as delivery_count
    from {{ ref('fct_d6_daily_city_payouts') }}
    group by delivery_date, city_code

)

select
    coalesce(e.delivery_date, a.delivery_date) as delivery_date,
    coalesce(e.city_code,     a.city_code)     as city_code,
    e.delivery_count                           as expected_delivery_count,
    a.delivery_count                           as mart_delivery_count,
    a.mart_row_count
from expected e
full outer join actual a
    on  e.delivery_date = a.delivery_date
    and e.city_code     = a.city_code
where a.delivery_date is null          -- staging pair the mart never wrote
   or e.delivery_date is null          -- mart row with nothing behind it
   or a.mart_row_count <> 1            -- not exactly one row
   or e.delivery_count <> a.delivery_count
