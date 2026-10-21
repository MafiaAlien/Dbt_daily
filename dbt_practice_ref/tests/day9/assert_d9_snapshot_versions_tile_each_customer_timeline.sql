-- V6: per customer_id, versions tile the timeline:
-- exactly one open version (and it is the latest), every closed version ends exactly where
-- the next begins (no gap, no overlap), and no window is empty.
with versions as (

    select
        customer_id,
        dbt_valid_from,
        dbt_valid_to,
        lead(dbt_valid_from) over (
            partition by customer_id
            order by dbt_valid_from
        ) as next_valid_from
    from {{ ref('snap_d9_customers') }}

),

open_version_counts as (

    select
        customer_id,
        sum(case when dbt_valid_to is null then 1 else 0 end) as open_versions
    from versions
    group by customer_id

),

violations as (

    select
        customer_id,
        cast(null as timestamp)        as dbt_valid_from,
        'not exactly one open version' as failure
    from open_version_counts
    where open_versions <> 1

    union all

    select
        customer_id,
        dbt_valid_from,
        'open version is not the latest'
    from versions
    where dbt_valid_to is null
      and next_valid_from is not null

    union all

    select
        customer_id,
        dbt_valid_from,
        'gap or overlap with next version'
    from versions
    where dbt_valid_to is not null
      and (next_valid_from is null or dbt_valid_to <> next_valid_from)

    union all

    select
        customer_id,
        dbt_valid_from,
        'empty window'
    from versions
    where dbt_valid_to is not null
      and dbt_valid_to <= dbt_valid_from

)

select
    customer_id,
    dbt_valid_from,
    failure
from violations
