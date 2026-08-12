# dbt Daily Practice — Day 3

**Topic:** materialization trade-offs — view vs table vs ephemeral, and config precedence
(`dbt_project.yml` directory-level config vs an in-model `{{ config() }}` block)
**Difficulty:** Easy-Medium
**Prerequisite course:** dbt Fundamentals

## Problem

A SaaS company meters product usage and bills for it. The modelling here is deliberately
plain — no dedup, no dirty strings, no ambiguous grain. **Every hard decision this day
asks of you is about how a model is materialized, and about which lever sets that.**

Build six models across three layers.

### The materialization config you have been given

`dbt_practice/dbt_project.yml` already carries this block, and so does
`dbt_practice_ref/dbt_project.yml`:

```yaml
models:
  dbt_practice:
    day3:
      +materialized: view
      marts:
        +materialized: table
```

That block is **not** a complete specification of this day. It is the starting state.
Read it together with the per-model requirements below and work out, for each model,
whether it already lands on the right materialization or whether you have to do
something about it — and if so, *where*.

Two rules on how you may fix a mismatch:

- **You may add in-model `{{ config() }}` blocks.** Unlike Day 2, they are allowed here;
  the point of the day is knowing when they are the right tool.
- **You must not change the `day3:` block in `dbt_project.yml`.** It is shared with the
  reference project, and the reference solution is generated against exactly the block
  printed above. Leave both copies alone.

### Layer 1 — staging

Rename to `snake_case`, cast to the stated type, and nothing else: no filtering, no
aggregation, no deduplication. Each is 1:1 with its seed.

`stg_d3_plans` — from seed `raw_d3_plans`. **Grain: one row per `plan_code`.** 5 rows.

| column | type | source column |
|---|---|---|
| `plan_code` | varchar | `PLAN_CODE` |
| `plan_name` | varchar | `PLAN_NAME` |
| `tier` | varchar | `TIER` |
| `monthly_price_usd` | `decimal(10,2)` | `MONTHLY_PRICE_USD` |

`monthly_price_usd` is **nullable on purpose**: a NULL there means the plan is
custom-priced, which is a fact about the plan, not missing data. Do not coalesce it away.

`stg_d3_subscriptions` — from seed `raw_d3_subscriptions`.
**Grain: one row per `subscription_id`.** 7 rows.

| column | type | source column |
|---|---|---|
| `subscription_id` | varchar | `SUBSCRIPTION_ID` |
| `account_id` | varchar | `ACCOUNT_ID` |
| `plan_code` | varchar | `PLAN_CODE` |
| `status` | varchar | `STATUS` |
| `started_on` | date | `STARTED_ON` |

`stg_d3_usage_events` — from seed `raw_d3_usage_events`.
**Grain: one row per `event_id`.** 14 rows.

| column | type | source column |
|---|---|---|
| `event_id` | varchar | `EVENT_ID` |
| `subscription_id` | varchar | `SUBSCRIPTION_ID` |
| `event_date` | date | `EVENT_DATE` |
| `metric` | varchar | `METRIC` |
| `units` | integer | `UNITS` |
| `is_billable` | boolean | `IS_BILLABLE` |

`units` is **nullable on purpose**: some meters report an event without a quantity.
Pass it through unchanged, NULLs and all. Handling it is the mart's job, not staging's.

### Layer 2 — intermediate

`int_d3_billable_usage` — **must be `ephemeral`.**

**Grain: one row per `event_id` that is billable AND belongs to an active subscription.**
It keeps exactly the events that are eligible to be charged for.

| column | definition |
|---|---|
| `event_id` | from `stg_d3_usage_events` |
| `subscription_id` | from `stg_d3_usage_events` |
| `plan_code` | the plan of that event's subscription |
| `event_date` | from `stg_d3_usage_events` |
| `units` | from `stg_d3_usage_events`, **unchanged — do not coalesce here** |

An event is kept when both hold:

- `is_billable` is true, **and**
- its subscription's `status` is `'active'` (`'churned'` and `'trialing'` are excluded)

**This model contains 8 rows.** You cannot check that by querying it — see the note
below. Take it as part of the spec.

> **An ephemeral model is not built.** dbt compiles it into a CTE inside each model that
> `ref()`s it. There is no view and no table in the database afterwards, so
> `select * from int_d3_billable_usage` will fail, and it will not appear in
> `information_schema.tables`. That absence is asserted by one of the tests below.
> Debrief question 3 is about what you do instead when you need to see its rows.

### Layer 3 — marts

Both marts read staging and the intermediate via `ref()`. Neither may read a seed
directly.

#### `fct_d3_plan_usage` — must be a **table**

**Grain: one row per `plan_code` that appears in `stg_d3_subscriptions`.** A plan in the
catalogue that nobody has ever subscribed to does **not** produce a row here.

| column | definition |
|---|---|
| `plan_code` | grain. Never null. |
| `subscription_count` | count of subscriptions on this plan, **in any status**. |
| `active_subscription_count` | count of those whose `status` is `'active'`. Zero if none. |
| `billable_event_count` | count of rows in `int_d3_billable_usage` for this plan. **An event whose `units` is missing is still an event and still counts.** A plan with no billable events has `0`. |
| `billable_units` | **sum of `units` over those same rows.** An event with a missing `units` contributes `0`. A plan with no billable events at all has `0`. Type integer. **Never null.** |

Read the last two rows of that table against each other before you write the aggregate.
They are counted over the same set of rows and they do not fail in the same way.

#### `dim_d3_plan_current` — must be a **view**

**Grain: one row per `plan_code` in `stg_d3_plans`** — the whole catalogue, including
plans with no subscriptions. 5 rows.

| column | definition |
|---|---|
| `plan_code` | grain. Never null. |
| `plan_name` | from `stg_d3_plans`. |
| `tier` | from `stg_d3_plans`. |
| `monthly_price_usd` | from `stg_d3_plans`, **nullable**. |
| `is_custom_priced` | boolean: true when `monthly_price_usd` is null, false otherwise. Never null. |

Why this one is a view and the fact table is not: the catalogue is five rows that change
a few times a year, and the BI layer must never show a price the catalogue no longer
lists. A table here buys nothing and adds a rebuild between a price change and the number
an account manager reads. Debrief question 4 asks you to argue the reverse case.

## Input

All three files are already written to `dbt_practice/seeds/day3/` and loaded — you do not
create them. They are shown here so the data is readable next to the requirements.

`raw_d3_plans.csv`

```csv
PLAN_CODE,PLAN_NAME,TIER,MONTHLY_PRICE_USD
starter,Starter,entry,29.00
growth,Growth,mid,99.50
scale,Scale,mid,299.00
enterprise,Enterprise,top,
legacy_basic,Legacy Basic,entry,19.99
```

`raw_d3_subscriptions.csv`

```csv
SUBSCRIPTION_ID,ACCOUNT_ID,PLAN_CODE,STATUS,STARTED_ON
S001,A100,starter,active,2026-01-15
S002,A101,growth,active,2026-01-20
S003,A102,growth,churned,2026-02-01
S004,A103,scale,active,2026-02-10
S005,A104,starter,trialing,2026-03-01
S006,A105,enterprise,active,2026-03-05
S007,A106,scale,churned,2026-03-12
```

`raw_d3_usage_events.csv`

```csv
EVENT_ID,SUBSCRIPTION_ID,EVENT_DATE,METRIC,UNITS,IS_BILLABLE
E0001,S001,2026-03-01,api_calls,1200,true
E0002,S001,2026-03-02,api_calls,800,true
E0003,S001,2026-03-02,storage_gb,15,false
E0004,S002,2026-03-01,api_calls,5000,true
E0005,S002,2026-03-03,api_calls,,true
E0006,S002,2026-03-04,storage_gb,40,true
E0007,S003,2026-03-01,api_calls,9000,true
E0008,S004,2026-03-02,storage_gb,120,false
E0009,S004,2026-03-05,storage_gb,60,false
E0010,S005,2026-03-01,api_calls,300,true
E0011,S006,2026-03-03,api_calls,,true
E0012,S006,2026-03-06,api_calls,,true
E0013,S007,2026-03-07,api_calls,700,true
E0014,S001,2026-03-08,api_calls,450,true
```

An empty field is a missing value — not a zero, not an empty string.

## Expected Output

Comparison is **order-insensitive** for both marts; sorted by `plan_code` here only for
readability.

`fct_d3_plan_usage` — exactly 4 rows.

| plan_code | subscription_count | active_subscription_count | billable_event_count | billable_units |
|---|---|---|---|---|
| enterprise | 1 | 1 | 2 | 0 |
| growth | 2 | 1 | 3 | 5040 |
| scale | 2 | 1 | 0 | 0 |
| starter | 2 | 1 | 3 | 2450 |

`dim_d3_plan_current` — exactly 5 rows. An empty cell is NULL.

| plan_code | plan_name | tier | monthly_price_usd | is_custom_priced |
|---|---|---|---|---|
| enterprise | Enterprise | top |  | true |
| growth | Growth | mid | 99.50 | false |
| legacy_basic | Legacy Basic | entry | 19.99 | false |
| scale | Scale | mid | 299.00 | false |
| starter | Starter | entry | 29.00 | false |

**Row counts and the two zero-vs-null columns are part of the answer.** A solution can
pass every generic test in the suite below and still be wrong in `fct_d3_plan_usage`.
Compare the table, not just the test summary.

## Verification

Use the files in this section **verbatim**. They are the acceptance criteria: do not
weaken, remove, or add tests in order to make a run go green.

`dbt_practice/models/day3/staging/schema.yml`

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

`dbt_practice/models/day3/intermediate/schema.yml`

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

`dbt_practice/models/day3/marts/schema.yml`

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

### The two singular tests

No generic test can check a materialization, so these assert it directly against the
catalogue. A singular test passes when it returns **zero rows**. Copy both verbatim.

`dbt_practice/tests/day3/assert_d3_materializations.sql`

```sql
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
```

`dbt_practice/tests/day3/assert_d3_intermediate_is_ephemeral.sql`

```sql
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
```

Pass condition: `dbt build --select path:models/day3` is green **and** both marts match
Expected Output exactly.

Suggested loop while working:

```
docker compose exec dbt dbt build --select path:models/day3
```

`path:models/day3` does not rebuild the seeds — they are already loaded.

**One warning about stale relations.** If you build a model as a view or table and later
change it to `ephemeral`, dbt does **not** drop what it already created. The old relation
stays in `practice.duckdb` and `assert_d3_intermediate_is_ephemeral` keeps failing on a
ghost. `practice.duckdb` is disposable — rebuild clean:

```
docker compose exec dbt bash -c "rm -f practice.duckdb && dbt seed && dbt build --select path:models/day3"
```

## Deliverables

```
dbt_practice/models/day3/staging/stg_d3_plans.sql
dbt_practice/models/day3/staging/stg_d3_subscriptions.sql
dbt_practice/models/day3/staging/stg_d3_usage_events.sql
dbt_practice/models/day3/staging/schema.yml
dbt_practice/models/day3/intermediate/int_d3_billable_usage.sql
dbt_practice/models/day3/intermediate/schema.yml
dbt_practice/models/day3/marts/fct_d3_plan_usage.sql
dbt_practice/models/day3/marts/dim_d3_plan_current.sql
dbt_practice/models/day3/marts/schema.yml
dbt_practice/tests/day3/assert_d3_materializations.sql
dbt_practice/tests/day3/assert_d3_intermediate_is_ephemeral.sql
```

Plus, in `days/day3/notes.md`: written English answers to the Debrief questions, and any
assumption you had to make recorded under `## Assumptions`. Day 2's `notes.md` was left
blank; that is a logged recurring pattern, and this file is a deliverable like any other.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **Config precedence.** List every level at which `materialized` can be set for
   `dim_d3_plan_current`, in order of who wins, and say where the `day3:` block sits in
   that order. Then: the problem forbade editing `dbt_project.yml`, but suppose it had
   not, and you had made the mart a view by changing `marts: +materialized: view` there
   instead. Name what breaks, and which test tells you.

2. **Trade-off.** `int_d3_billable_usage` is ephemeral. Give the argument for ephemeral
   over a view here, then name the condition under which you would reverse it — be
   concrete about what changes in the compiled SQL when a second, then a fifth, mart
   `ref()`s the same ephemeral model. Then say which of the two is cheaper to *operate*
   at 3am when the fact table's numbers are wrong.

3. You cannot `select * from int_d3_billable_usage`, and it does not appear in
   `information_schema.tables`. Describe how you would inspect its 8 rows anyway — name
   the dbt command and the file it produces. Then state what that tells you about where
   an ephemeral model's SQL actually executes.

4. **Trade-off.** `dim_d3_plan_current` is a view over a 5-row catalogue and
   `fct_d3_plan_usage` is a table. Describe the input change that would make you flip
   each one to the other materialization, in terms of the quantity you would actually
   measure to decide. Then name the third option dbt offers for the fact table when it
   gets large enough that a full rebuild stops being acceptable, and say what that option
   costs you in correctness guarantees.
