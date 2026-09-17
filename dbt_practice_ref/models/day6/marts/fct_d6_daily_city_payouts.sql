{{ config(
    unique_key=['delivery_date', 'city_code'],
    incremental_strategy='delete+insert',
    on_schema_change='fail'
) }}

-- materialized: incremental is set in dbt_project.yml (day6/marts), not here.

with scoped as (

    select *
    from {{ ref('int_d6_delivery_payouts') }}

    {% if is_incremental() %}

    -- LATE ARRIVALS. A delivery loads no later than 4 calendar days after its
    -- delivery_date, and a delivery_date is never later than its own load date.
    -- So every row in tonight's batch has delivery_date >= (load date - 4), and
    -- the mart's max delivery_date is <= that load date. Nothing can therefore
    -- arrive below (mart max delivery_date - 4): a safe, closed lookback window.
    --
    -- Every date inside the window is recomputed IN FULL from staging, which
    -- holds every batch <= d6_batch — not only tonight's rows. Combined with
    -- delete+insert on the grain, the window is replaced wholesale rather than
    -- appended to, so a reopened day lands at its complete value.
    --
    -- DuckDB: date - integer subtracts days. Portable alternative:
    --   dateadd('day', -4, max(delivery_date))
    where delivery_date >= (
        select coalesce(max(delivery_date), date '1900-01-01') - 4
        from {{ this }}
    )

    {% endif %}

),

agg as (

    select
        delivery_date,
        city_code,
        count(*)                                                as delivery_count,
        sum(case when status = 'COMPLETED' then 1 else 0 end)   as completed_count,
        sum(payout_base_usd)                                    as payout_base_usd,
        sum(adjustment_total_usd)                               as adjustment_total_usd
    from scoped
    group by delivery_date, city_code

)

select
    delivery_date,
    city_code,
    cast(delivery_count      as integer)       as delivery_count,
    cast(completed_count     as integer)       as completed_count,
    cast(payout_base_usd     as decimal(10,2)) as payout_base_usd,
    cast(adjustment_total_usd as decimal(10,2)) as adjustment_total_usd,
    cast(payout_base_usd + adjustment_total_usd as decimal(10,2)) as total_payout_usd
from agg
