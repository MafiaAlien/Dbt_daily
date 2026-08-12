-- An ephemeral model is compiled into its consumers as a CTE. It is never built, so it
-- must leave nothing behind in the database. Any row returned here means
-- int_d3_billable_usage was materialized as a view or a table instead.
--
-- depends_on: {{ ref('fct_d3_plan_usage') }}

select
    table_name,
    table_type

from information_schema.tables
where table_schema = 'main'
  and table_name = 'int_d3_billable_usage'