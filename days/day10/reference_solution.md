I wrote this without a dbt runtime, so nothing below has been executed. The expected tables were checked by hand against the seeds, and the `FAIL n` values in `notes.md` are predictions you need to replace with the pasted lines.

`dbt_practice/models/day10/staging/stg_d10_orders.sql`
```sql
{{ config(materialized='view') }}

select
    cast(order_id as varchar)      as order_id,
    cast(merchant_id as varchar)   as merchant_id,
    cast(ordered_at as timestamp)  as ordered_at
from {{ ref('raw_d10_orders') }}
```

`dbt_practice/models/day10/staging/stg_d10_payments.sql`
```sql
{{ config(materialized='view') }}

select
    cast(payment_id as varchar)                          as payment_id,
    cast(order_id as varchar)                            as order_id,
    -- a blank method stays missing (NULL); staging never substitutes a label
    nullif(lower(cast(payment_method as varchar)), '')   as payment_method,
    cast(status as varchar)                              as status,
    cast(amount_usd as decimal(10, 2))                   as amount_usd,
    cast(paid_at as timestamp)                           as paid_at
from {{ ref('raw_d10_payments') }}
```

`dbt_practice/models/day10/staging/schema.yml`
```yaml
version: 2

models:
  - name: stg_d10_orders
    description: One row per order.
    columns:
      - name: order_id
        data_tests:
          - unique
          - not_null
      - name: merchant_id
        data_tests:
          - not_null
      - name: ordered_at
        data_tests:
          - not_null

  - name: stg_d10_payments
    description: One row per payment attempt. payment_method is lower-cased and may be null.
    columns:
      - name: payment_id
        data_tests:
          - unique
          - not_null
      - name: order_id
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d10_orders')
              field: order_id
      - name: payment_method
      - name: status
        data_tests:
          - not_null
          - accepted_values:
              values: ['captured', 'failed']
      - name: amount_usd
        data_tests:
          - not_null
      - name: paid_at
```

`dbt_practice/models/day10/intermediate/int_d10_captured_payments.sql`
```sql
{{ config(materialized='view') }}

with payments as (

    select
        payment_id,
        order_id,
        payment_method,
        amount_usd
    from {{ ref('stg_d10_payments') }}
    where status = 'captured'

),

orders as (

    select
        order_id,
        merchant_id,
        -- month of the ORDER, not of paid_at.
        -- date_trunc('month', ts) works on DuckDB/Postgres/Snowflake; BigQuery: date_trunc(date(ts), month)
        cast(date_trunc('month', ordered_at) as date) as order_month
    from {{ ref('stg_d10_orders') }}

)

select
    payments.payment_id,
    payments.order_id,
    orders.merchant_id,
    orders.order_month,
    payments.payment_method,
    payments.amount_usd
from payments
inner join orders
    on payments.order_id = orders.order_id
```

`dbt_practice/models/day10/intermediate/schema.yml`
```yaml
version: 2

models:
  - name: int_d10_captured_payments
    description: One row per captured payment, with the merchant and month of the order it pays for.
    columns:
      - name: payment_id
        data_tests:
          - unique
          - not_null
      - name: order_id
        data_tests:
          - not_null
      - name: merchant_id
        data_tests:
          - not_null
      - name: order_month
        data_tests:
          - not_null
      - name: payment_method
      - name: amount_usd
        data_tests:
          - not_null
```

`dbt_practice/models/day10/marts/fct_d10_merchant_month_payments.sql`
```sql
{{ config(materialized='table') }}

{#- The only place the method list comes from. Lower-cased to match staging. -#}
{%- set methods = var('d10_payment_methods') | map('lower') | list -%}

with orders as (

    select
        order_id,
        merchant_id,
        -- date_trunc('month', ts) works on DuckDB/Postgres/Snowflake; BigQuery: date_trunc(date(ts), month)
        cast(date_trunc('month', ordered_at) as date) as order_month
    from {{ ref('stg_d10_orders') }}

),

merchant_months as (

    select
        merchant_id,
        order_month,
        count(*) as order_count
    from orders
    group by
        merchant_id,
        order_month

),

captured as (

    select
        merchant_id,
        order_month,
        order_id,
        payment_method,
        amount_usd,
        {%- if methods %}
        -- a missing method is "other"; the explicit null check is needed because null not in (...) is null
        (
            payment_method is null
            or payment_method not in ({{ "'" ~ methods | join("', '") ~ "'" }})
        ) as is_other_method
        {%- else %}
        true as is_other_method
        {%- endif %}
    from {{ ref('int_d10_captured_payments') }}

),

payment_metrics as (

    select
        merchant_id,
        order_month,
        sum(amount_usd) as captured_amount_usd,
        {%- for m in methods %}
        count(distinct case when payment_method = '{{ m }}' then order_id end) as {{ m }}_order_count,
        sum(case when payment_method = '{{ m }}' then amount_usd end) as {{ m }}_amount_usd,
        {%- endfor %}
        count(distinct case when is_other_method then order_id end) as other_order_count,
        sum(case when is_other_method then amount_usd end) as other_amount_usd
    from captured
    group by
        merchant_id,
        order_month

)

select
    merchant_months.merchant_id,
    merchant_months.order_month,
    cast(merchant_months.order_count as integer) as order_count,
    cast(coalesce(payment_metrics.captured_amount_usd, 0) as decimal(12, 2)) as captured_amount_usd,
    {%- for m in methods %}
    cast(coalesce(payment_metrics.{{ m }}_order_count, 0) as integer) as {{ m }}_order_count,
    cast(coalesce(payment_metrics.{{ m }}_amount_usd, 0) as decimal(12, 2)) as {{ m }}_amount_usd,
    {%- endfor %}
    cast(coalesce(payment_metrics.other_order_count, 0) as integer) as other_order_count,
    cast(coalesce(payment_metrics.other_amount_usd, 0) as decimal(12, 2)) as other_amount_usd
from merchant_months
left join payment_metrics
    on merchant_months.merchant_id = payment_metrics.merchant_id
    and merchant_months.order_month = payment_metrics.order_month
```

`dbt_practice/models/day10/marts/schema.yml`
```yaml
version: 2

models:
  - name: fct_d10_merchant_month_payments
    description: >
      One row per merchant per month with at least one order placed. Per-method columns are
      generated from var d10_payment_methods and are covered by the singular tests in
      tests/day10, not listed here.
    columns:
      - name: merchant_id
        data_tests:
          - not_null
      - name: order_month
        data_tests:
          - not_null
      - name: order_count
        data_tests:
          - not_null
      - name: captured_amount_usd
        data_tests:
          - not_null
```

`dbt_practice/tests/day10/assert_d10_generated_columns_populated.sql` (V5)
```sql
-- V5: every generated column is not null and not negative, on every row.
{%- set prefixes = (var('d10_payment_methods') | map('lower') | list) + ['other'] %}

select
    merchant_id,
    order_month
from {{ ref('fct_d10_merchant_month_payments') }}
where
    {%- for p in prefixes %}
    {{ 'or ' if not loop.first else '' }}{{ p }}_order_count is null
    or {{ p }}_order_count < 0
    or {{ p }}_amount_usd is null
    or {{ p }}_amount_usd < 0
    {%- endfor %}
```

`dbt_practice/tests/day10/assert_d10_methods_partition_captured_amount.sql` (V6)
```sql
-- V6: per-method amounts plus other add up to captured_amount_usd on every row.
{%- set methods = var('d10_payment_methods') | map('lower') | list %}

with totals as (

    select
        merchant_id,
        order_month,
        captured_amount_usd,
        {%- for m in methods %}
        {{ m }}_amount_usd +
        {%- endfor %}
        other_amount_usd as methods_amount_usd
    from {{ ref('fct_d10_merchant_month_payments') }}

)

select
    merchant_id,
    order_month,
    captured_amount_usd,
    methods_amount_usd
from totals
-- null-safe on purpose: a null on either side must fail, not vanish
where captured_amount_usd is distinct from methods_amount_usd
```

`dbt_practice/tests/day10/assert_d10_mart_grain_unique.sql` (V7)
```sql
-- V7: no two rows share (merchant_id, order_month).
select
    merchant_id,
    order_month,
    count(*) as row_count
from {{ ref('fct_d10_merchant_month_payments') }}
group by
    merchant_id,
    order_month
having count(*) > 1
```

`dbt_practice/tests/day10/assert_d10_mart_ties_to_staging.sql` (V8)
```sql
-- V8: mart totals tie out to staging (deliberately not to the int).
with mart as (

    select
        coalesce(sum(order_count), 0)          as order_count,
        coalesce(sum(captured_amount_usd), 0)  as captured_amount_usd
    from {{ ref('fct_d10_merchant_month_payments') }}

),

staged_orders as (

    select count(*) as order_count
    from {{ ref('stg_d10_orders') }}

),

staged_payments as (

    select coalesce(sum(amount_usd), 0) as captured_amount_usd
    from {{ ref('stg_d10_payments') }}
    where status = 'captured'

)

select
    mart.order_count                     as mart_order_count,
    staged_orders.order_count            as staging_order_count,
    mart.captured_amount_usd             as mart_captured_amount_usd,
    staged_payments.captured_amount_usd  as staging_captured_amount_usd
from mart
cross join staged_orders
cross join staged_payments
where mart.order_count <> staged_orders.order_count
    or mart.captured_amount_usd <> staged_payments.captured_amount_usd
```

`notes.md` (wherever earlier days keep it; it contains no quoted method names, so it is safe even inside a grepped folder)
```markdown
# Day 10 notes

## Test count (written before run 1)

| block | assertions |
|---|---|
| V1 stg_d10_orders | 4 (unique + not_null on order_id; not_null on merchant_id, ordered_at) |
| V2 stg_d10_payments | 7 (unique + not_null on payment_id; not_null on order_id, status, amount_usd; accepted_values; relationships) |
| V3 int_d10_captured_payments | 6 (unique + not_null on payment_id; not_null on order_id, merchant_id, order_month, amount_usd) |
| V4 mart, generic | 4 |
| V5–V8 mart, singular | 4 |
| **Total** | **25** |

`dbt ls --resource-type test ...` must print 25 lines. The count is the same on run 2,
because V5 and V6 are one test each however many methods the var holds. Each build
therefore reports 29 nodes: 4 models + 25 tests.

## Why V8 reads staging, not the int

The mart is built from the int. If V8 also read the int, both sides of the comparison
would share the same captured filter and the same join to orders, so a bug there (failed
payments let through, payments dropped or fanned out by the join) would move both totals
together and the test would stay green. Staging sits upstream of all of that logic, so
it is an independent figure.

## Red proof

NOT YET RUN. The n values are what the seed data should produce under the default var.
Replace each "expected" line with the pasted `FAIL n` line, and revert after each.

### V5 — assert_d10_generated_columns_populated
Change (mart, final select): `cast(coalesce(payment_metrics.other_order_count, 0) as integer)`
became `cast(payment_metrics.other_order_count as integer)`.
Expected: FAIL 1 (M3, 2026-09-01: orders but no captured payment, so the left join
leaves a null). V6 and V8 stay green.

### V6 — assert_d10_methods_partition_captured_amount
Change (mart, `captured` CTE): removed `payment_method is null or` from is_other_method,
so payments with no method fall out of every bucket.
Expected: FAIL 2 (M1 2026-09-01, 175.50 vs 187.50; M3 2026-10-01, 200.00 vs 218.00).
V5 and V8 stay green.

### V8 — assert_d10_mart_ties_to_staging
Change (int_d10_captured_payments): removed `where status = 'captured'`.
Expected: FAIL 1 (mart 1210.50 vs staging 960.50; order counts still 13 = 13).
V5 and V6 stay green, which is the point of reading staging.
```

## Design notes

- **Materialization:** it is set with `config()` at the top of each model, because the `day10:` block in `dbt_project.yml` is off-limits and I can't see what it sets. If that block already does this, the in-model lines are redundant but harmless.
- **"Other" bucket:** it is one boolean, `is_other_method`, computed once in the `captured` CTE. The explicit `is null` branch is needed because `null not in (...)` is null, which would silently drop the two no-method payments. An empty var list compiles to `true` rather than an invalid `in ()`.
- **Null-safe tests:** V6 uses `is distinct from` and V8 coalesces its sums. With a plain `<>`, a null would make the comparison null and the test could never go red.
- **Var handling:** it is lower-cased in Jinja so it matches staging's lower-cased methods. It has no default in `var()`, so a missing var is a compile error, not a silently empty pivot. Values must be valid SQL identifiers, since they become column names.
- **YAML syntax:** `schema.yml` uses `data_tests:` with top-level test arguments, which needs dbt 1.8+. On an older version, rename the key to `tests:`.