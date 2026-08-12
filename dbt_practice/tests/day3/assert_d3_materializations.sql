-- Asserts that every day-3 model that IS built is built as the problem requires.
-- Returns one row per relation that is missing or has the wrong table_type.
--
-- The depends_on comments put this test downstream of the marts in the DAG, so
-- `--select path:models/day3` picks it up and runs it after they are built.
--
-- depends_on: {{ ref('fct_d3_plan_usage') }}
-- depends_on: {{ ref('dim_d3_plan_current') }}

with expected as (

    select 'stg_d3_plans'         as table_name, 'VIEW'       as table_type
    union all select 'stg_d3_subscriptions', 'VIEW'
    union all select 'stg_d3_usage_events',  'VIEW'
    union all select 'fct_d3_plan_usage',    'BASE TABLE'
    union all select 'dim_d3_plan_current',  'VIEW'

),

actual as (

    select table_name, table_type
    from information_schema.tables
    where table_schema = 'main'

)

select
    expected.table_name,
    expected.table_type as expected_table_type,
    actual.table_type   as actual_table_type

from expected
left join actual on actual.table_name = expected.table_name
where actual.table_type is null
   or actual.table_type <> expected.table_type