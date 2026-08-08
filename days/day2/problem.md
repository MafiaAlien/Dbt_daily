# dbt Daily Practice — Day 2

**Topic:** sources vs seeds — `source()`, source freshness config, and renaming/typing
discipline in staging
**Difficulty:** Easy
**Prerequisite course:** dbt Fundamentals

## Problem

An e-commerce company has two very different kinds of raw input, and the point of this
day is that they are referenced differently.

1. **The ERP order export.** An external ERP system drops a full order snapshot into the
   warehouse every night. **dbt does not build this table.** dbt is only *told it exists*
   via a `sources:` block, and models read it with `source()`.
2. **A country → region lookup.** A small mapping table the analytics team owns and edits
   by hand. It lives in the repo as a CSV, **dbt does build it**, and models read it with
   `ref()`.

> **Read this before you start — how the local environment fakes a source.**
> There is no external warehouse here, so `raw_d2_orders` was physically loaded into
> `practice.duckdb` by `dbt seed` before you got this problem. That is a local
> convenience, not the lesson. For this exercise it is a **source**: you declare it in a
> `sources:` block and read it with `source('erp', 'orders')`, and you must **not**
> `ref()` it. One consequence is real and worth noticing while you work: a source is not
> a node dbt builds, so nothing upstream of your staging model appears in the build
> plan. Debrief question 2 is about exactly that.

Build three models across two layers.

### Layer 0 — the source declaration (not a model)

Declare the ERP export in `dbt_practice/models/day2/staging/sources.yml`:

| setting | value |
|---|---|
| source name | `erp` |
| schema | `main` |
| table name | `orders` |
| identifier | `raw_d2_orders` |
| `loaded_at_field` | `EXPORTED_AT` |
| freshness | warn after **12 hours**, error after **24 hours** |

Also add `not_null` tests on the source's `ORDER_ID` and `EXPORTED_AT` columns.

Two constraints on this block:

- **Do not write a `database:` key.** It must resolve against whatever target the
  project runs on, and this same declaration will later be run against a different
  DuckDB file.
- **Do not put a `unique` test on the source's `ORDER_ID`.** See the grain rule below —
  decide for yourself which object that constraint actually describes, and put it there.

### Layer 1 — staging (materialized as **view**)

Staging renames to `snake_case` and casts to the stated type. Beyond that, each model
does exactly what its grain rule says and nothing more — no filtering, no aggregation.

`stg_d2_orders` — from `source('erp', 'orders')`

| column | type | source column | note |
|---|---|---|---|
| `order_id` | integer | `ORDER_ID` | |
| `customer_id` | varchar | `CUSTOMER_CODE` | |
| `country_code` | varchar | `COUNTRY_CODE` | pass through unchanged |
| `order_status` | varchar | `ORDER_STATUS` | **normalised: trimmed and lower-cased** |
| `ordered_at` | timestamp | `ORDER_TS` | |
| `amount_usd` | `decimal(12,2)` | `AMOUNT_USD` | cast explicitly; do not leave it floating-point |
| `exported_at` | timestamp | `EXPORTED_AT` | |

**Grain: one row per `order_id`.**

The ERP re-sends an order whenever it is corrected downstream, so the same `ORDER_ID`
can appear in the export more than once, with a later `EXPORTED_AT` and possibly a
different status or amount. **Keep the whole row with the greatest `EXPORTED_AT` for
that `ORDER_ID`, and discard the earlier one(s).** No two rows for the same `ORDER_ID`
share an `EXPORTED_AT` in this data, so the winner is unambiguous.

`stg_d2_country_region` — from seed `raw_d2_country_region`, read with `ref()`

| column | type | source column | note |
|---|---|---|---|
| `country_code` | varchar | `country_code` | |
| `region` | varchar | `region` | |

**Grain: one row per `country_code`.** 1:1 with the seed — every seed row appears here.

### Layer 2 — mart (materialized as **table**)

`fct_d2_region_revenue` — **grain: one row per region that appears in `stg_d2_orders`.**

A region "appears in `stg_d2_orders`" when at least one order in `stg_d2_orders` maps to
it, in **any** status. Consequences, both of which are load-bearing:

- A country in `stg_d2_country_region` that no order was placed from does **not** produce
  a row in this mart.
- An order whose `country_code` is not in `stg_d2_country_region` is **not** dropped. It
  belongs to the region `'Unmapped'`, which is a row of this mart like any other.

| column | definition |
|---|---|
| `region` | the region from `stg_d2_country_region`, or the literal `'Unmapped'` when the order's `country_code` has no row there. Never null. |
| `total_order_count` | count of orders in `stg_d2_orders` mapping to this region, **in any status**. |
| `completed_order_count` | count of those orders whose `order_status` is `'completed'`. A region with no completed orders has `0`. |
| `gross_revenue_usd` | **sum of `amount_usd` over the completed orders only.** A completed order whose `amount_usd` is missing contributes `0`. A region with no completed orders at all has `0.00`. Never null. Type `decimal(12,2)`. |

### Layering rules

- The mart reads staging via `ref()`. It must not read a seed or a source directly.
- Materializations are already configured for you in `dbt_project.yml` under the `day2:`
  block — do not add per-model `config()` blocks to override them.

## Input

Both files are already written to `dbt_practice/seeds/day2/` and loaded — you do not
create them. Shown here so the data is readable next to the requirements.

`raw_d2_orders.csv` — **the ERP export. Read it with `source()`, not `ref()`.**

```csv
ORDER_ID,CUSTOMER_CODE,COUNTRY_CODE,ORDER_STATUS,ORDER_TS,AMOUNT_USD,EXPORTED_AT
5001,C001,US,completed,2026-03-01 09:12:00,120.00,2026-03-02 02:00:00
5002,C002,US,Completed,2026-03-01 15:40:00,80.50,2026-03-02 02:00:00
5003,C003,CA,pending,2026-03-02 11:05:00,45.00,2026-03-03 02:00:00
5003,C003,CA,COMPLETED,2026-03-02 11:05:00,49.00,2026-03-04 02:00:00
5004,C004,GB,completed ,2026-03-02 18:22:00,,2026-03-03 02:00:00
5005,C005,DE,cancelled,2026-03-03 08:00:00,200.00,2026-03-04 02:00:00
5006,C006,JP,Completed,2026-03-03 20:15:00,310.25,2026-03-04 02:00:00
5007,C001,US, pending,2026-03-04 07:45:00,60.00,2026-03-05 02:00:00
5008,C007,GB,completed,2026-03-04 12:30:00,75.25,2026-03-05 02:00:00
5009,C008,CA,CANCELLED,2026-03-05 09:00:00,15.00,2026-03-06 02:00:00
5010,C002,US,completed,2026-03-05 16:10:00,99.99,2026-03-06 02:00:00
5011,C009,AU,Cancelled,2026-03-05 19:40:00,42.00,2026-03-06 02:00:00
```

`raw_d2_country_region.csv` — **the analytics-owned lookup. Read it with `ref()`.**

```csv
country_code,region
US,NORAM
CA,NORAM
GB,EMEA
DE,EMEA
AU,APAC
MX,LATAM
```

An empty field is a missing value, not a zero and not an empty string. Whitespace inside
a field is part of the value — it was in the export, so it is in the table.

## Expected Output

`fct_d2_region_revenue` — comparison is **order-insensitive**; sorted by `region` here
only for readability.

| region | total_order_count | completed_order_count | gross_revenue_usd |
|---|---|---|---|
| APAC | 1 | 0 | 0.00 |
| EMEA | 3 | 2 | 75.25 |
| NORAM | 6 | 4 | 349.49 |
| Unmapped | 1 | 1 | 310.25 |

Exactly 4 rows. `stg_d2_orders` has exactly 11 rows.

**Row count is part of the answer.** A solution can pass every test in the suite below
and still produce the wrong number of rows here. Compare the table, not just the test
summary.

## Verification

Use these two `schema.yml` files **verbatim**. They are the acceptance criteria: do not
weaken, remove, or add tests in order to make a run go green. (`sources.yml` is yours to
write — its two `not_null` tests are specified in Layer 0 above.)

`dbt_practice/models/day2/staging/schema.yml`

```yaml
version: 2

models:
  - name: stg_d2_orders
    description: "One row per order_id, taken from the latest ERP export of that order."
    columns:
      - name: order_id
        description: "Natural key of the order, and the grain of this model."
        data_tests:
          - unique
          - not_null
      - name: order_status
        description: "Normalised order status."
        data_tests:
          - not_null
          - accepted_values:
              arguments:
                values: ["completed", "pending", "cancelled"]
      - name: country_code
        description: "Two-letter country code exactly as the ERP sent it."
        data_tests:
          - not_null
      - name: exported_at
        description: "Export timestamp of the winning row."
        data_tests:
          - not_null

  - name: stg_d2_country_region
    description: "One row per country_code, mapping a country to an analytics region."
    columns:
      - name: country_code
        description: "Two-letter country code, and the grain of this model."
        data_tests:
          - unique
          - not_null
      - name: region
        description: "Analytics region this country rolls up to."
        data_tests:
          - not_null
```

`dbt_practice/models/day2/marts/schema.yml`

```yaml
version: 2

models:
  - name: fct_d2_region_revenue
    description: "One row per region present in stg_d2_orders."
    columns:
      - name: region
        description: "Grain of this model."
        data_tests:
          - unique
          - not_null
      - name: total_order_count
        description: "Orders in this region, any status."
        data_tests:
          - not_null
      - name: completed_order_count
        description: "Completed orders in this region. Zero if none."
        data_tests:
          - not_null
      - name: gross_revenue_usd
        description: "Captured revenue over completed orders. Zero if none. Never null."
        data_tests:
          - not_null
```

Pass condition: `dbt build --select path:models/day2` is green **and**
`fct_d2_region_revenue` matches Expected Output exactly.

Suggested loop while working:

```
docker compose exec dbt dbt build --select path:models/day2
```

Note that `path:models/day2` does not rebuild the seeds — they are already loaded — and
a source is never built at all.

### Source freshness

Separately from `dbt build`, run:

```
docker compose exec dbt dbt source freshness --select source:erp
```

This is **not** part of the pass condition, and it is **expected to report a failing
state** — the export is a fixed snapshot from March 2026, so it is stale by any
threshold. That is the point. Paste the output verbatim into `days/day2/notes.md` and
answer debrief question 4 about it.

## Deliverables

```
dbt_practice/models/day2/staging/sources.yml
dbt_practice/models/day2/staging/stg_d2_orders.sql
dbt_practice/models/day2/staging/stg_d2_country_region.sql
dbt_practice/models/day2/staging/schema.yml
dbt_practice/models/day2/marts/fct_d2_region_revenue.sql
dbt_practice/models/day2/marts/schema.yml
```

Plus, in `days/day2/notes.md`: the `dbt source freshness` output, written English answers
to the Debrief questions, and any assumption you had to make recorded under
`## Assumptions`.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **Trade-off.** Day 1 stated that staging must not deduplicate; Day 2 requires
   `stg_d2_orders` to deduplicate. Give the argument behind each convention, then say
   which layer you would put this dedup in if five different marts consumed the same ERP
   export, and name the condition that would make you reverse that choice.

2. `raw_d2_orders` was physically loaded into the database by `dbt seed`, yet you read it
   with `source()`. Name the edge that is missing from the DAG because of that, describe
   one concrete production failure it makes possible, and state what a source actually is
   in a real project — what is on the other end of that declaration, and who owns it.

3. There is deliberately **no** `relationships` test from `stg_d2_orders.country_code` to
   `stg_d2_country_region.country_code`. State precisely what such a test would assert,
   say whether it would pass on this data and why, and explain what that tells you about
   where the `'Unmapped'` requirement has to be implemented.

4. **Trade-off.** `warn_after` and `error_after` in a freshness block: say exactly what
   quantity they measure and what an orchestrator should do differently on each. Then
   name a real situation where you would set `error_after` much *looser* than 24 hours,
   and one where 24 hours is already far too loose — and say what it is about the source
   that decides it.
