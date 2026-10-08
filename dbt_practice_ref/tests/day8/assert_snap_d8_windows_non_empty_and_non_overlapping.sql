-- V5: windows are [dbt_valid_from, dbt_valid_to), NULL = open-ended.
-- No window is empty, and no two versions of the same employee overlap.
with versions as (

    select
        employee_id,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (
            partition by employee_id
            order by dbt_valid_from, dbt_valid_to nulls last
        ) as version_seq
    from {{ ref('snap_d8_employees') }}

),

empty_windows as (

    select
        employee_id,
        'empty window' as failure,
        dbt_valid_from as from_a,
        dbt_valid_to   as to_a,
        cast(null as timestamp) as from_b,
        cast(null as timestamp) as to_b
    from versions
    where dbt_valid_to is not null
      and dbt_valid_to <= dbt_valid_from

),

overlaps as (

    select
        a.employee_id,
        'overlapping windows' as failure,
        a.dbt_valid_from as from_a,
        a.dbt_valid_to   as to_a,
        b.dbt_valid_from as from_b,
        b.dbt_valid_to   as to_b
    from versions as a
    join versions as b
        on  a.employee_id = b.employee_id
        and a.version_seq < b.version_seq
    where (b.dbt_valid_to is null or a.dbt_valid_from < b.dbt_valid_to)
      and (a.dbt_valid_to is null or b.dbt_valid_from < a.dbt_valid_to)

)

select * from empty_windows
union all
select * from overlaps
