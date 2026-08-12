## Models

**`dbt_practice/models/day3/staging/stg_d3_plans.sql`**

```sql
-- Materialization: inherited from dbt_project.yml (day3: +materialized: view). No
-- in-model config needed — this model already lands on the required view.

select
    cast(PLAN_CODE as varchar)               as plan_code,
    cast(PLAN_NAME as varchar)               as plan_name,
    cast(TIER as varchar)                    as tier,
    cast(MONTHLY_PRICE_USD as decimal(10,2)) as monthly_price_usd

from {{ ref('raw_d3_plans') }}
```

**`dbt_practice/models/day3/staging/stg_d3_subscriptions.sql`**

```sql
-- Materialization: inherited view from the day3: block.

select
    cast(SUBSCRIPTION_ID as varchar) as subscription_id,
    cast(ACCOUNT_ID as varchar)      as account_id,
    cast(PLAN_CODE as varchar)       as plan_code,
    cast(STATUS as varchar)          as status,
    cast(STARTED_ON as date)         as started_on

from {{ ref('raw_d3_subscriptions') }}
```

**`dbt_practice/models/day3/staging/stg_d3_usage_events.sql`**

```sql
-- Materialization: inherited view from the day3: block.

select
    cast(EVENT_ID as varchar)        as event_id,
    cast(SUBSCRIPTION_ID as varchar) as subscription_id,
    cast(EVENT_DATE as date)         as event_date,
    cast(METRIC as varchar)          as metric,
    cast(UNITS as integer)           as units,
    cast(IS_BILLABLE as boolean)     as is_billable

from {{ ref('raw_d3_usage_events') }}
```

**`dbt_practice/models/day3/intermediate/int_d3_billable_usage.sql`**

```sql
{{ config(materialized = 'ephemeral') }}

-- The day3: block would make this a view. `intermediate` has no sub-block of its own and
-- dbt_project.yml is off-limits, so the override has to live in the model.

with usage_events as (

    select * from {{ ref('stg_d3_usage_events') }}

),

subscriptions as (

    select * from {{ ref('stg_d3_subscriptions') }}

)

select
    usage_events.event_id,
    usage_events.subscription_id,
    subscriptions.plan_code,
    usage_events.event_date,
    usage_events.units

from usage_events
inner join subscriptions
    on subscriptions.subscription_id = usage_events.subscription_id

where usage_events.is_billable
  and subscriptions.status = 'active'
```

**`dbt_practice/models/day3/marts/fct_d3_plan_usage.sql`**

```sql
-- Materialization: inherited table from the marts: sub-block. No in-model config needed.

with subscriptions as (

    select * from {{ ref('stg_d3_subscriptions') }}

),

billable_usage as (

    select * from {{ ref('int_d3_billable_usage') }}

),

subscriptions_by_plan as (

    select
        plan_code,
        count(*)                                            as subscription_count,
        count(case when status = 'active' then 1 end)       as active_subscription_count
    from subscriptions
    group by plan_code

),

usage_by_plan as (

    select
        plan_code,
        count(event_id)             as billable_event_count,
        sum(coalesce(units, 0))     as billable_units
    from billable_usage
    group by plan_code

)

select
    subscriptions_by_plan.plan_code,
    subscriptions_by_plan.subscription_count,
    subscriptions_by_plan.active_subscription_count,
    coalesce(usage_by_plan.billable_event_count, 0)          as billable_event_count,
    cast(coalesce(usage_by_plan.billable_units, 0) as integer) as billable_units

from subscriptions_by_plan
left join usage_by_plan
    on usage_by_plan.plan_code = subscriptions_by_plan.plan_code
```

**`dbt_practice/models/day3/marts/dim_d3_plan_current.sql`**

```sql
{{ config(materialized = 'view') }}

-- The marts: sub-block would make this a table. dbt_project.yml is off-limits and a
-- per-model override in YAML would still be a project-file edit, so it goes here.

select
    plan_code,
    plan_name,
    tier,
    monthly_price_usd,
    monthly_price_usd is null as is_custom_priced

from {{ ref('stg_d3_plans') }}
```

## Schema files

**`dbt_practice/models/day3/staging/schema.yml`**

```yaml
version: 2

models:
  - name: stg_d3_plans
    description: "One row per plan_code. 1:1 with the plan catalogue seed."
    columns:
      - name: plan_code
        description: "Natural key of the plan, and the grain of this model."
        data_tests:
          - unique
          - not_null
      - name: plan_name
        description: "Display name of the plan."
        data_tests:
          - not_null
      - name: tier
        description: "Pricing tier the plan belongs to."
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ["entry", "mid", "top"]
      - name: monthly_price_usd
        description: "List price. NULL means custom-priced — deliberately not tested for nullability."

  - name: stg_d3_subscriptions
    description: "One row per subscription_id. 1:1 with the subscription seed."
    columns:
      - name: subscription_id
        description: "Natural key of the subscription, and the grain of this model."
        data_tests:
          - unique
          - not_null
      - name: plan_code
        description: "Plan this subscription is on."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_d3_plans')
                field: plan_code
      - name: status
        description: "Lifecycle state of the subscription."
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ["active", "churned", "trialing"]

  - name: stg_d3_usage_events
    description: "One row per event_id. 1:1 with the usage event seed."
    columns:
      - name: event_id
        description: "Natural key of the event, and the grain of this model."
        data_tests:
          - unique
          - not_null
      - name: subscription_id
        description: "Subscription the event was metered against."
        data_tests:
          - not_null
          - relationships:
              arguments:
                to: ref('stg_d3_subscriptions')
                field: subscription_id
      - name: is_billable
        description: "Whether this event is eligible to be charged for."
        data_tests:
          - not_null
      - name: units
        description: "Metered quantity. NULL where the meter reported no quantity — deliberately not tested for nullability."
```

**`dbt_practice/models/day3/intermediate/schema.yml`**

```yaml
version: 2

models:
  - name: int_d3_billable_usage
    description: "One row per billable usage event on an active subscription. Ephemeral — inlined as a CTE, never built."
    columns:
      - name: event_id
        description: "Grain of this model."
        data_tests:
          - unique
          - not_null
      - name: plan_code
        description: "Plan the event's subscription is on."
        data_tests:
          - not_null
```

**`dbt_practice/models/day3/marts/schema.yml`**

```yaml
version: 2

models:
  - name: fct_d3_plan_usage
    description: "One row per plan_code present in stg_d3_subscriptions."
    columns:
      - name: plan_code
        description: "Grain of this model."
        data_tests:
          - unique
          - not_null
      - name: subscription_count
        description: "Subscriptions on this plan, any status."
        data_tests:
          - not_null
      - name: active_subscription_count
        description: "Active subscriptions on this plan. Zero if none."
        data_tests:
          - not_null
      - name: billable_event_count
        description: "Billable events on active subscriptions. Zero if none. Counts events with a missing units value."
        data_tests:
          - not_null
      - name: billable_units
        description: "Billable units on active subscriptions. Zero if none. Never null."
        data_tests:
          - not_null

  - name: dim_d3_plan_current
    description: "One row per plan in the catalogue, including plans with no subscriptions."
    columns:
      - name: plan_code
        description: "Grain of this model."
        data_tests:
          - unique
          - not_null
      - name: plan_name
        description: "Display name of the plan."
        data_tests:
          - not_null
      - name: tier
        description: "Pricing tier the plan belongs to."
        data_tests:
          - not_null
      - name: is_custom_priced
        description: "True when the plan has no list price."
        data_tests:
          - not_null
```

## Design notes

- Only two models need an in-model `config()`. The three staging models take `view` from the `day3:` block, and `fct_d3_plan_usage` takes `table` from the nested `marts:` block. `int_d3_billable_usage` and `dim_d3_plan_current` are the two whose required materialization contradicts what they inherit, and since `dbt_project.yml` is frozen the override has to sit in the model file.
- The fact grain comes from `stg_d3_subscriptions`, not from the plan catalogue: aggregating subscriptions first and **left** joining usage onto that gives `scale` its row (2 subs, 0 events) while keeping `legacy_basic` out entirely.
- `billable_event_count` and `billable_units` fail differently over the same rows. `count(event_id)` already ignores nothing that matters — a NULL `units` is still a row — but `sum(units)` would skip those NULLs and return NULL for a plan with no rows at all. Hence `sum(coalesce(units, 0))` inside the aggregate (fixes enterprise → 0 rather than NULL) *and* `coalesce(..., 0)` outside the left join (fixes scale, which has no row to aggregate).
- The NULL-preserving contract is enforced upstream by omission: staging casts `units` and `monthly_price_usd` and does nothing else, and the intermediate passes `units` through untouched. Zero-substitution happens exactly once, in the mart that needs a number.
- `monthly_price_usd is null` yields a real boolean in DuckDB, Postgres, and Snowflake; on engines without a boolean type (e.g. Oracle) this would need a `case when ... then 1 else 0 end`. Everything else here is plain ANSI SQL — no DuckDB-specific functions are used.