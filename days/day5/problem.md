# dbt Daily Practice — Day 5

**Topic:** incremental models — `materialized='incremental'`, `is_incremental()`,
`unique_key`, and the watermark that decides which rows a run recomputes
**Difficulty:** Medium
**Prerequisite course:** Incremental Models

## Problem

A fulfilment company loads two warehouse feeds every night. You are building the daily
warehouse mart that finance reads each morning. It has to be **incremental**: a nightly
run may not rebuild three years of history to add one day.

The whole day turns on one question — *which rows does tonight's run recompute, and what
happens to the rows it recomputes over?* Everything else is the setup that makes the
answer visible.

### The feeds

Both feeds are **append-only**. Neither is ever updated in place.

- `raw_d5_shipments` — the shipment header feed. A shipment is written when it leaves
  the warehouse and **written again** whenever its status changes. The feed therefore
  carries **more than one row for the same `shipment_id`**, distinguished by
  `updated_at`. It is not a shipment table; it is a log of shipment states.
- `raw_d5_shipment_items` — the item line feed. One row per item line, written once.

Each row carries a `batch_id`: which nightly load delivered it. `batch_id = 1` is
last night's load, `batch_id = 2` is tonight's.

**Feed guarantee — write this one down, question 3 comes back to it:** a batch never
carries a shipment whose `ship_date` is *earlier* than the newest `ship_date` already
delivered by the previous batch. The tail of the most recent day can arrive late; a day
that is already closed never reopens.

### Simulating two nightly runs

There is no scheduler here, so the batch boundary is a var. Both staging models end with
exactly this clause — copy it verbatim, it is not the exercise:

```sql
where batch_id <= {{ var('d5_batch', 1) }}
```

Run 1 leaves the var at its default and sees batch 1 only. Run 2 passes
`--vars '{d5_batch: 2}'` and sees batches 1 and 2. Exact commands are in
`## Verification`.

### Layer 1 — staging (views)

`stg_d5_shipments` — from seed `raw_d5_shipments`.
**Grain: one row per row of the feed — 9 rows at `d5_batch=1`, 16 rows at `d5_batch=2`.**
Not one row per shipment. Rename and cast only; no dedup, no filtering beyond the
`batch_id` clause above.

| column | type | source column |
|---|---|---|
| `shipment_id` | varchar | `SHIPMENT_ID` |
| `warehouse_code` | varchar | `WAREHOUSE_CODE` |
| `ship_date` | date | `SHIP_DATE` |
| `status` | varchar | `STATUS` |
| `shipping_cost_usd` | `decimal(10,2)` | `SHIPPING_COST_USD` |
| `updated_at` | timestamp | `UPDATED_AT` |

`stg_d5_shipment_items` — from seed `raw_d5_shipment_items`.
**Grain: one row per `item_id` — 16 rows at `d5_batch=1`, 24 rows at `d5_batch=2`.**

| column | type | source column |
|---|---|---|
| `item_id` | varchar | `ITEM_ID` |
| `shipment_id` | varchar | `SHIPMENT_ID` |
| `sku` | varchar | `SKU` |
| `quantity` | integer | `QUANTITY` |
| `line_weight_kg` | `decimal(9,3)` | `LINE_WEIGHT_KG` |

`batch_id` is used by the filter and is **not** published out of either staging model.
Both models expose exactly the columns listed above, in that order.

### Layer 2 — intermediate (optional)

`dbt_practice/models/day5/intermediate/` exists and is yours. It has no
`dbt_project.yml` entry, so anything you put there materializes as a **view** under the
project default. Nothing forces you to use it. If you build one, name it `int_d5_*` and
say in `notes.md` what it buys.

### Layer 3 — mart

#### `fct_d5_daily_warehouse_shipments` — incremental

**Grain: one row per (`ship_date`, `warehouse_code`).**

`dbt_project.yml` configures `day5/marts` as `table`. The mart must be `incremental`.
Work out where that override belongs — **`dbt_project.yml` is not yours to edit this
day**, its `day5:` block stays exactly as it is.

Configuration you must decide and then justify in `notes.md`:

- `unique_key` — which column or columns.
- `on_schema_change` — set it explicitly rather than inheriting the default.
- `incremental_strategy` — **leave it unset**, at the adapter default. Name that
  default in `notes.md`, and say how you found out what it is.

**Which shipment row counts.** A shipment is represented by its **latest** feed row —
the one with the greatest `updated_at` for that `shipment_id`. Earlier rows for the same
shipment are superseded and contribute nothing, to any column. `updated_at` is unique
within a `shipment_id`.

**Which shipments count.** A shipment whose latest status is `CANCELLED` is excluded
entirely — from every count, from every sum, and from the item lines it owns. A
(`ship_date`, `warehouse_code`) pair whose shipments are *all* cancelled produces **no
row at all**, not a row of zeros.

Columns:

| column | type | definition |
|---|---|---|
| `ship_date` | date | grain |
| `warehouse_code` | varchar | grain |
| `shipment_count` | integer | number of shipments on that date at that warehouse, latest status not `CANCELLED` |
| `delivered_count` | integer | of those, the number whose latest status is `DELIVERED` |
| `shipping_cost_usd` | `decimal(10,2)` | sum of the **header** `shipping_cost_usd` over those shipments |
| `item_quantity` | integer | sum of `quantity` over the item lines belonging to those shipments |
| `total_weight_kg` | `decimal(12,3)` | sum of `line_weight_kg` over the same item lines |

`shipping_cost_usd` is a **header-level** amount, charged once per shipment.
`item_quantity` and `total_weight_kg` are **line-level**. Three of the five measures are
counted or summed at one grain and two at another, and the mart publishes them on one
row. Fill in `## Grain plan` in `notes.md` before you write the `from` clause — see
`## Deliverables`.

A shipment with **no** item lines still counts in `shipment_count` and
`delivered_count`; its `item_quantity` and `total_weight_kg` contribution is `0`, never
`NULL`. The mart never publishes a `NULL` in any column.

## Input

`dbt_practice/seeds/day5/raw_d5_shipments.csv` — already loaded, do not edit.

```csv
SHIPMENT_ID,WAREHOUSE_CODE,SHIP_DATE,STATUS,SHIPPING_COST_USD,UPDATED_AT,BATCH_ID
S001,WH-A,2026-06-01,DELIVERED,12.50,2026-06-01 18:00:00,1
S002,WH-A,2026-06-01,DELIVERED,9.00,2026-06-01 18:00:00,1
S003,WH-A,2026-06-01,CANCELLED,7.25,2026-06-01 18:00:00,1
S004,WH-B,2026-06-01,IN_TRANSIT,15.00,2026-06-01 18:00:00,1
S005,WH-B,2026-06-02,DELIVERED,11.00,2026-06-02 18:00:00,1
S006,WH-B,2026-06-02,IN_TRANSIT,8.75,2026-06-02 18:00:00,1
S007,WH-C,2026-06-02,CANCELLED,6.00,2026-06-02 18:00:00,1
S008,WH-A,2026-06-03,IN_TRANSIT,10.00,2026-06-03 11:00:00,1
S009,WH-C,2026-06-03,IN_TRANSIT,13.50,2026-06-03 11:00:00,1
S008,WH-A,2026-06-03,DELIVERED,10.00,2026-06-04 07:00:00,2
S009,WH-C,2026-06-03,DELIVERED,11.75,2026-06-04 07:00:00,2
S010,WH-A,2026-06-03,DELIVERED,14.25,2026-06-04 07:00:00,2
S011,WH-B,2026-06-03,DELIVERED,9.50,2026-06-04 07:00:00,2
S012,WH-A,2026-06-04,IN_TRANSIT,16.00,2026-06-05 07:00:00,2
S013,WH-B,2026-06-04,DELIVERED,12.00,2026-06-05 07:00:00,2
S014,WH-B,2026-06-04,CANCELLED,5.50,2026-06-05 07:00:00,2
```

`dbt_practice/seeds/day5/raw_d5_shipment_items.csv` — already loaded, do not edit.

```csv
ITEM_ID,SHIPMENT_ID,SKU,QUANTITY,LINE_WEIGHT_KG,BATCH_ID
I001,S001,SKU-100,2,1.500,1
I002,S001,SKU-101,1,0.750,1
I003,S001,SKU-102,3,2.250,1
I004,S002,SKU-100,1,0.750,1
I005,S003,SKU-103,4,3.000,1
I006,S003,SKU-104,2,1.000,1
I007,S004,SKU-101,5,3.750,1
I008,S004,SKU-105,1,0.400,1
I009,S005,SKU-100,3,2.250,1
I010,S006,SKU-102,2,1.500,1
I011,S006,SKU-103,1,0.750,1
I012,S006,SKU-106,6,2.400,1
I013,S007,SKU-100,2,1.500,1
I014,S008,SKU-107,1,5.000,1
I015,S008,SKU-101,2,1.500,1
I016,S009,SKU-100,4,3.000,1
I017,S010,SKU-102,3,2.250,2
I018,S010,SKU-108,1,0.900,2
I019,S011,SKU-100,2,1.500,2
I020,S012,SKU-103,1,0.750,2
I021,S012,SKU-104,2,1.000,2
I022,S012,SKU-109,5,4.500,2
I023,S014,SKU-100,1,0.750,2
I024,S014,SKU-105,2,0.800,2
```

## Expected Output

Two snapshots of the same table, ordered by `ship_date`, then `warehouse_code`. **Both
are graded.** Getting run 2 right by rebuilding from scratch is not a pass.

### After run 1 — `d5_batch` at its default, mart built with `--full-refresh` (5 rows)

| ship_date | warehouse_code | shipment_count | delivered_count | shipping_cost_usd | item_quantity | total_weight_kg |
|---|---|---|---|---|---|---|
| 2026-06-01 | WH-A | 2 | 2 | 21.50 | 7 | 5.250 |
| 2026-06-01 | WH-B | 1 | 0 | 15.00 | 6 | 4.150 |
| 2026-06-02 | WH-B | 2 | 1 | 19.75 | 12 | 6.900 |
| 2026-06-03 | WH-A | 1 | 0 | 10.00 | 3 | 6.500 |
| 2026-06-03 | WH-C | 1 | 0 | 13.50 | 4 | 3.000 |

### After run 2 — `--vars '{d5_batch: 2}'`, **incremental**, no `--full-refresh` (8 rows)

| ship_date | warehouse_code | shipment_count | delivered_count | shipping_cost_usd | item_quantity | total_weight_kg |
|---|---|---|---|---|---|---|
| 2026-06-01 | WH-A | 2 | 2 | 21.50 | 7 | 5.250 |
| 2026-06-01 | WH-B | 1 | 0 | 15.00 | 6 | 4.150 |
| 2026-06-02 | WH-B | 2 | 1 | 19.75 | 12 | 6.900 |
| 2026-06-03 | WH-A | 2 | 2 | 24.25 | 7 | 9.650 |
| 2026-06-03 | WH-B | 1 | 1 | 9.50 | 2 | 1.500 |
| 2026-06-03 | WH-C | 1 | 1 | 11.75 | 4 | 3.000 |
| 2026-06-04 | WH-A | 1 | 0 | 16.00 | 8 | 6.250 |
| 2026-06-04 | WH-B | 1 | 1 | 12.00 | 0 | 0.000 |

Three of the run-1 rows are unchanged in run 2. Two of them change. One date gains a
warehouse it did not have. That distribution is the whole point of the exercise —
if your run 2 leaves 2026-06-03 looking the way run 1 left it, the mart is wrong and
every test will still be green.

## Verification

### Tests you must write

Days 1–3 handed you `schema.yml`. Day 4 gave you a prose contract. This one is in
between: the generic tests are named, the rest are stated as intent and you translate
them.

**No packages.** `dbt_utils` and friends are installed; they are out of bounds this day.
Anything the four built-in generic tests cannot express is a **singular test** in
`dbt_practice/tests/day5/`, one file per assertion, named after what it asserts.

**V1 — `stg_d5_shipments`.** `not_null` on `shipment_id`, `warehouse_code`, `ship_date`,
`status`, `shipping_cost_usd`, `updated_at`. `accepted_values` on `status`:
`DELIVERED`, `IN_TRANSIT`, `CANCELLED`. **No `unique` test on `shipment_id`** — this
model's grain is the feed row, and a `unique` here would be asserting something the feed
does not promise. Do not add one out of habit.

**V2 — `stg_d5_shipment_items`.** `unique` and `not_null` on `item_id`. `not_null` on
`shipment_id`, `quantity`, `line_weight_kg`. `relationships` from `shipment_id` to
`stg_d5_shipments.shipment_id`.

**V3 — mart, generic.** `not_null` on all seven columns.

**V4 — mart, intent.** No two rows of the mart share the same
(`ship_date`, `warehouse_code`). No package — write it yourself.

**V5 — mart, intent.** Every row has `shipment_count >= 1`.

**V6 — mart, intent.** Every row has `delivered_count <= shipment_count`.

V4, V5 and V6 must be part of `dbt build`, so they run on **both** runs, not just when
you remember to invoke them.

### The two runs

```bash
# Run 1 — first nightly batch. --full-refresh builds the mart from scratch.
docker compose exec dbt dbt build --select path:models/day5 --full-refresh

# capture the run-1 table before touching anything else
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d5_daily_warehouse_shipments') }} order by 1,2" --limit 20

# Run 2 — second nightly batch, INCREMENTAL. No --full-refresh.
docker compose exec dbt dbt build --select path:models/day5 --vars '{d5_batch: 2}'

# capture the run-2 table
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d5_daily_warehouse_shipments') }} order by 1,2" --limit 20
```

### The equivalence check — run it last

An incremental model is only correct if it agrees with the model it is an optimization
of. **After** you have captured run 2's output:

```bash
docker compose exec dbt dbt build --select path:models/day5 --vars '{d5_batch: 2}' --full-refresh
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d5_daily_warehouse_shipments') }} order by 1,2" --limit 20
```

This must return exactly what run 2 returned, cell for cell. It destroys the
incrementally-built table, which is why it goes last — capture run 2 first or you will
be re-running the whole protocol.

### Pass condition

All four of the following, or it is not a pass:

1. Both runs green — `ERROR=0`, `WARN=0`, `SKIP=0`, and the mart actually materialized.
2. Run 1's table matches the 5-row snapshot cell for cell, including column types.
3. Run 2's table matches the 8-row snapshot cell for cell, including column types.
4. The full-refresh rebuild matches run 2 cell for cell.

Green tests are necessary and not sufficient. Every trap this day survives a green
build; the only thing that catches them is comparing cells.

## Deliverables

```
dbt_practice/models/day5/staging/stg_d5_shipments.sql
dbt_practice/models/day5/staging/stg_d5_shipment_items.sql
dbt_practice/models/day5/staging/schema.yml
dbt_practice/models/day5/marts/fct_d5_daily_warehouse_shipments.sql
dbt_practice/models/day5/marts/schema.yml
dbt_practice/tests/day5/          (one .sql per intent assertion — V4, V5, V6)
```

Plus, in `days/day5/notes.md`:

- `## Grain plan` — **a graded deliverable, and the first thing you write.** One row per
  mart column, filled in *before* any SQL:

  | Column | Grain it is computed at | Aggregation | Filter | Comes from |
  |---|---|---|---|---|
  | `shipment_count` | one shipment | count | latest row per shipment, status <> CANCELLED | `stg_d5_shipments` |

  Then one sentence naming, for each source model, how many rows of it can match a
  single row of the other — and what that means for the order you aggregate in.

  This exists because the same defect has now landed four days running (Day 1, Day 2,
  Day 3, Day 4). Day 4's problem file warned about it in plain text and it landed
  anyway. The conclusion in the blindspot log was that the gap is not knowledge but
  **sequence** — the grain gets recognised after the `from` clause instead of before it.
  This table is the sequence, written down.

- `## Assumptions` — anything you had to decide.

- `## Config decisions` — `unique_key`, `on_schema_change`, and the adapter's default
  `incremental_strategy`: what you chose, and how you found the default.

- `## Run log` — the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from all three runs, plus
  the three captured tables, pasted. Not summarized, pasted.

- `## Debrief answers` — the four questions below, in written English.

`notes.md` has now been left blank or near-blank on Days 1, 2, 3 and 4, and on Day 4 the
missing table was itself worth two defects. Treat it as code.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **The boundary.** Quote your `is_incremental()` block. Then, using the actual
   `ship_date` values in this data: name the exact rows that end up in the mart if the
   comparison is `>` instead of `>=`, and name the exact rows that are wrong if it is
   `>=` with no `unique_key` at all. Then state the general rule tying the comparison
   operator to the presence of `unique_key` — one of them makes the other safe, and
   without it the other is a bug.

2. **Trade-off — the key.** `unique_key='ship_date'` and
   `unique_key=['ship_date','warehouse_code']` both produce the correct table for this
   data. Construct a second batch — concrete rows — under which they produce different
   tables, and say which `incremental_strategy` you assumed while constructing it. Then
   say which you would ship, and the condition under which you would reverse the choice.

3. **What the watermark rests on.** The feed guarantee in `## Problem` says a batch never
   carries a shipment older than the newest one already delivered. Name the exact line of
   your model that depends on that guarantee. Describe what the mart looks like the first
   morning the guarantee is broken — which rows are wrong, and which of your six tests
   fires. Then name (do not implement) the pattern that survives it, and say what it
   costs.

4. **Trade-off — where the grain is enforced.** This mart folds a header feed and a line
   feed into one row. Name the failure a header-level measure suffers when the two are
   joined before either is aggregated; say which of your five measures is exposed to it
   and which is not, and why. Then write the singular test that would have caught it, and
   explain why none of the four built-in generic tests can express that assertion. Last:
   that test costs a full scan of both models on every run — say when you would keep it
   in `dbt build` and when you would move it somewhere cheaper, and where that is.
