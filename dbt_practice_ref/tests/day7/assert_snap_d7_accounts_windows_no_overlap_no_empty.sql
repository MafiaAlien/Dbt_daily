-- V6: SCD2 integrity. Windows are [dbt_valid_from, dbt_valid_to), NULL dbt_valid_to = open.
-- Fails on (a) an empty or inverted window, (b) any two windows of one account that overlap —
-- including exact duplicates, which is why rows are numbered rather than compared by dbt_scd_id.
with windows as (

    select
        account_id,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (
            partition by account_id
            order by dbt_valid_from, dbt_valid_to
        ) as window_seq
    from {{ ref('snap_d7_accounts') }}

),

empty_windows as (

    select
        account_id,
        'empty_window'                as failure,
        dbt_valid_from                as window_a_from,
        dbt_valid_to                  as window_a_to,
        cast(null as timestamp)       as window_b_from,
        cast(null as timestamp)       as window_b_to
    from windows
    where dbt_valid_to is not null
      and dbt_valid_to <= dbt_valid_from

),

overlapping_windows as (

    select
        a.account_id,
        'overlap'                     as failure,
        a.dbt_valid_from              as window_a_from,
        a.dbt_valid_to                as window_a_to,
        b.dbt_valid_from              as window_b_from,
        b.dbt_valid_to                as window_b_to
    from windows as a
    join windows as b
        on  a.account_id = b.account_id
        and a.window_seq < b.window_seq
    -- half-open intervals overlap iff each starts before the other ends
    where (b.dbt_valid_to is null or a.dbt_valid_from < b.dbt_valid_to)
      and (a.dbt_valid_to is null or b.dbt_valid_from < a.dbt_valid_to)

)

select * from empty_windows
union all
select * from overlapping_windows
