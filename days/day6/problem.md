# dbt Daily Practice — Day 6

**Topic:** late-arriving data — what an incremental model does when a row shows up for a
day the mart has already closed, and what `--full-refresh` does and does not prove
**Difficulty:** Medium-Hard
**Prerequisite course:** Incremental Models

## Problem

A food-delivery marketplace pays couriers per delivery. You are building the daily
city-level payout mart that finance reconciles against the bank file every morning. It
is **incremental** — three years of history are not rebuilt to add one night.

Day 5 handed you a guarantee: *a day that is already closed never reopens.* **This day
takes that guarantee away.** Couriers' phones sync offline work; adjustments are keyed
in by city ops with a lag. Rows for a day you already published will keep arriving after
you published it.

The whole day turns on one question — *tonight's batch contains a row for a day the mart
already has. Does that day get recomputed, and is the recomputed answer complete?*
Everything else is the setup that makes the answer visible.

### The feeds

Both feeds are **append-only**. Neither is ever updated in place.

- `raw_d6_deliveries` — the delivery feed. **Write-once: exactly one row per
  `delivery_id`, ever.** A delivery is written when it is finalised, and its `STATUS` is
  final at that moment. There is no restatement in this feed.
- `raw_d6_delivery_adjustments` — the adjustment line feed. Zero, one, or several lines
  per delivery: tips, surge top-ups, penalties. A delivery may have none.

Each row carries a `BATCH_ID`: which nightly load delivered it. The header feed also
carries `LOADED_AT`, the timestamp of that load.

- `BATCH_ID = 1` — loaded `2026-07-02 03:00`
- `BATCH_ID = 2` — loaded `2026-07-04 03:00`
- `BATCH_ID = 3` — loaded `2026-07-05 03:00`

**Adjustment guarantee:** an adjustment line arrives in the same batch as the delivery it
belongs to. There are no orphan lines and no lines that outlive their delivery's batch.

**The late-arrival SLA — write this one down, questions 1 and 2 come back to it:** a
delivery is loaded **no later than 4 calendar days** after its `DELIVERY_DATE`. Nothing
older than that ever arrives. Compare that with the batch load dates above and with the
`DELIVERY_DATE` values in `## Input` before you write a single line of SQL.

### Simulating three nightly runs

There is no scheduler here, so the batch boundary is a var. Both staging models end with
exactly this clause — copy it verbatim, it is not the exercise:

```sql
where batch_id <= {{ var('d6_batch', 1) }}
```

Run 1 leaves the var at its default. Run 2 passes `--vars '{d6_batch: 2}'`, run 3
`--vars '{d6_batch: 3}'`. Exact commands are in `## Verification`. **All three runs are
graded, and so is a fourth rebuild.**

### Layer 1 — staging (views)

`stg_d6_deliveries` — from seed `raw_d6_deliveries`.
**Grain: one row per `delivery_id` — 5 rows at `d6_batch=1`, 12 at `d6_batch=2`, 17 at
`d6_batch=3`.** Rename and cast only; no filtering beyond the `batch_id` clause above.

| column | type | source column |
|---|---|---|
| `delivery_id` | varchar | `DELIVERY_ID` |
| `courier_id` | varchar | `COURIER_ID` |
| `city_code` | varchar | `CITY_CODE` |
| `delivery_date` | date | `DELIVERY_DATE` |
| `status` | varchar | `STATUS` |
| `payout_base_usd` | `decimal(10,2)` | `PAYOUT_BASE_USD` |
| `loaded_at` | timestamp | `LOADED_AT` |

`stg_d6_delivery_adjustments` — from seed `raw_d6_delivery_adjustments`.
**Grain: one row per `adjustment_id` — 8 rows at `d6_batch=1`, 15 at `d6_batch=2`, 21 at
`d6_batch=3`.**

| column | type | source column |
|---|---|---|
| `adjustment_id` | varchar | `ADJUSTMENT_ID` |
| `delivery_id` | varchar | `DELIVERY_ID` |
| `adj_type` | varchar | `ADJ_TYPE` |
| `adj_amount_usd` | `decimal(10,2)` | `ADJ_AMOUNT_USD` |

`batch_id` is used by the filter and is **not** published out of either staging model.
Both models expose exactly the columns listed above, in that order.

### Layer 2 — intermediate (optional)

`dbt_practice/models/day6/intermediate/` exists and is yours. It has no `dbt_project.yml`
entry, so anything you put there materializes as a **view** under the project default.
Nothing forces you to use it. If you build one, name it `int_d6_*` and say in `notes.md`
what it buys.

### Layer 3 — mart

#### `fct_d6_daily_city_payouts` — incremental

**Grain: one row per (`delivery_date`, `city_code`).**

`dbt_project.yml` already declares `day6/marts` as `+materialized: incremental`, so
materialization is settled and is **not** an in-model decision this day. Its `day6:`
block is not yours to edit.

What is not settled, and what you must decide and then justify in `notes.md`:

- `unique_key` — which column or columns.
- `incremental_strategy` — set it **explicitly** this time. Day 5 left it at the adapter
  default; name that default again and say whether you are matching it or overriding it.
- `on_schema_change` — set it explicitly rather than inheriting the default.

**Which deliveries count.** A delivery whose `status` is `CANCELLED` is excluded
entirely — from every count, from every sum, and from the adjustment lines it owns. A
(`delivery_date`, `city_code`) pair whose deliveries are *all* cancelled produces **no
row at all**, not a row of zeros.

Columns:

| column | type | definition |
|---|---|---|
| `delivery_date` | date | grain |
| `city_code` | varchar | grain |
| `delivery_count` | integer | number of non-cancelled deliveries on that date in that city |
| `completed_count` | integer | of those, the number whose `status` is `COMPLETED` |
| `payout_base_usd` | `decimal(10,2)` | sum of the **header** `payout_base_usd` over those deliveries |
| `adjustment_total_usd` | `decimal(10,2)` | sum of `adj_amount_usd` over the adjustment lines belonging to those deliveries |
| `total_payout_usd` | `decimal(10,2)` | `payout_base_usd + adjustment_total_usd` |

`payout_base_usd` is a **header-level** amount, paid once per delivery.
`adjustment_total_usd` is **line-level**. Three of the five measures are counted or
summed at one grain and one at another, and the mart publishes them on one row. Fill in
`## Grain plan` in `notes.md` before you write the `from` clause — see `## Deliverables`.

A delivery with **no** adjustment lines still counts in `delivery_count` and
`completed_count`; its `adjustment_total_usd` contribution is `0`, never `NULL`. The mart
never publishes a `NULL` in any column.

**The correctness standard for the incremental logic is stated once, here:** after every
run, the mart must contain exactly what a `--full-refresh` build at the same
`d6_batch` would contain. Not "the new day is right" — the whole table.

## Input

`dbt_practice/seeds/day6/raw_d6_deliveries.csv` — already loaded, do not edit.

```csv
DELIVERY_ID,COURIER_ID,CITY_CODE,DELIVERY_DATE,STATUS,PAYOUT_BASE_USD,LOADED_AT,BATCH_ID
D001,C-01,CT-A,2026-07-01,COMPLETED,8.00,2026-07-02 03:00:00,1
D002,C-02,CT-A,2026-07-01,COMPLETED,9.50,2026-07-02 03:00:00,1
D003,C-01,CT-A,2026-07-01,CANCELLED,4.00,2026-07-02 03:00:00,1
D004,C-03,CT-B,2026-07-01,RETURNED,6.25,2026-07-02 03:00:00,1
D005,C-04,CT-B,2026-07-01,COMPLETED,7.75,2026-07-02 03:00:00,1
D006,C-02,CT-A,2026-07-02,COMPLETED,10.00,2026-07-04 03:00:00,2
D007,C-05,CT-C,2026-07-02,COMPLETED,12.00,2026-07-04 03:00:00,2
D008,C-03,CT-B,2026-07-02,RETURNED,5.50,2026-07-04 03:00:00,2
D009,C-01,CT-A,2026-07-01,COMPLETED,8.50,2026-07-04 03:00:00,2
D010,C-04,CT-A,2026-07-03,COMPLETED,11.00,2026-07-04 03:00:00,2
D011,C-05,CT-C,2026-07-03,COMPLETED,9.00,2026-07-04 03:00:00,2
D012,C-02,CT-B,2026-07-03,CANCELLED,3.50,2026-07-04 03:00:00,2
D013,C-01,CT-A,2026-07-04,COMPLETED,7.00,2026-07-05 03:00:00,3
D014,C-06,CT-B,2026-07-04,COMPLETED,6.75,2026-07-05 03:00:00,3
D015,C-03,CT-C,2026-07-01,COMPLETED,13.00,2026-07-05 03:00:00,3
D016,C-06,CT-A,2026-07-01,COMPLETED,6.50,2026-07-05 03:00:00,3
D017,C-05,CT-C,2026-07-03,COMPLETED,10.50,2026-07-05 03:00:00,3
```

`dbt_practice/seeds/day6/raw_d6_delivery_adjustments.csv` — already loaded, do not edit.

```csv
ADJUSTMENT_ID,DELIVERY_ID,ADJ_TYPE,ADJ_AMOUNT_USD,BATCH_ID
A001,D001,TIP,2.00,1
A002,D001,SURGE,1.50,1
A003,D002,TIP,3.00,1
A004,D003,TIP,1.00,1
A005,D004,PENALTY,-2.00,1
A006,D005,TIP,1.25,1
A007,D005,SURGE,0.75,1
A008,D005,PENALTY,-0.50,1
A009,D006,TIP,2.50,2
A010,D007,TIP,4.00,2
A011,D007,SURGE,2.00,2
A012,D008,PENALTY,-1.50,2
A013,D009,TIP,1.75,2
A014,D010,TIP,3.25,2
A015,D010,SURGE,1.00,2
A016,D013,TIP,1.50,3
A017,D015,TIP,3.00,3
A018,D015,SURGE,1.50,3
A019,D015,PENALTY,-0.75,3
A020,D016,TIP,2.00,3
A021,D017,TIP,2.75,3
```

## Expected Output

Four snapshots of the same table, ordered by `delivery_date`, then `city_code`. **All
four are graded.** Getting run 3 right by rebuilding from scratch is not a pass — that is
what snapshot 4 is for, and it is checked against snapshot 3, not instead of it.

### After run 1 — `d6_batch` at its default, built with `--full-refresh` (2 rows)

| delivery_date | city_code | delivery_count | completed_count | payout_base_usd | adjustment_total_usd | total_payout_usd |
|---|---|---|---|---|---|---|
| 2026-07-01 | CT-A | 2 | 2 | 17.50 | 6.50 | 24.00 |
| 2026-07-01 | CT-B | 2 | 1 | 14.00 | -0.50 | 13.50 |

### After run 2 — `--vars '{d6_batch: 2}'`, **incremental**, no `--full-refresh` (7 rows)

| delivery_date | city_code | delivery_count | completed_count | payout_base_usd | adjustment_total_usd | total_payout_usd |
|---|---|---|---|---|---|---|
| 2026-07-01 | CT-A | 3 | 3 | 26.00 | 8.25 | 34.25 |
| 2026-07-01 | CT-B | 2 | 1 | 14.00 | -0.50 | 13.50 |
| 2026-07-02 | CT-A | 1 | 1 | 10.00 | 2.50 | 12.50 |
| 2026-07-02 | CT-B | 1 | 0 | 5.50 | -1.50 | 4.00 |
| 2026-07-02 | CT-C | 1 | 1 | 12.00 | 6.00 | 18.00 |
| 2026-07-03 | CT-A | 1 | 1 | 11.00 | 4.25 | 15.25 |
| 2026-07-03 | CT-C | 1 | 1 | 9.00 | 0.00 | 9.00 |

### After run 3 — `--vars '{d6_batch: 3}'`, **incremental**, no `--full-refresh` (10 rows)

| delivery_date | city_code | delivery_count | completed_count | payout_base_usd | adjustment_total_usd | total_payout_usd |
|---|---|---|---|---|---|---|
| 2026-07-01 | CT-A | 4 | 4 | 32.50 | 10.25 | 42.75 |
| 2026-07-01 | CT-B | 2 | 1 | 14.00 | -0.50 | 13.50 |
| 2026-07-01 | CT-C | 1 | 1 | 13.00 | 3.75 | 16.75 |
| 2026-07-02 | CT-A | 1 | 1 | 10.00 | 2.50 | 12.50 |
| 2026-07-02 | CT-B | 1 | 0 | 5.50 | -1.50 | 4.00 |
| 2026-07-02 | CT-C | 1 | 1 | 12.00 | 6.00 | 18.00 |
| 2026-07-03 | CT-A | 1 | 1 | 11.00 | 4.25 | 15.25 |
| 2026-07-03 | CT-C | 2 | 2 | 19.50 | 2.75 | 22.25 |
| 2026-07-04 | CT-A | 1 | 1 | 7.00 | 1.50 | 8.50 |
| 2026-07-04 | CT-B | 1 | 1 | 6.75 | 0.00 | 6.75 |

### After the rebuild — `--vars '{d6_batch: 3}' --full-refresh` (10 rows)

Identical to run 3, cell for cell.

**Read the three snapshots against each other before you write anything.** Run 2 leaves
2026-07-01 with 3 deliveries in CT-A and no CT-C row at all. Run 3 has to reach back and
change both — a date two days behind the newest date the mart has ever seen. That reach
is the exercise. If your run 3 leaves 2026-07-01 looking the way run 2 left it, the mart
is wrong, the bank file will not reconcile, and most of your tests will still be green.

## Verification

### Tests you must write

The generic tests are named; the singular ones are stated as intent and you translate
them.

**No packages.** `dbt_utils` and friends are installed; they are out of bounds this day.
Anything the four built-in generic tests cannot express is a **singular test** in
`dbt_practice/tests/day6/`, one file per assertion, named after what it asserts.

**V1 — `stg_d6_deliveries`, generic.** `unique` and `not_null` on `delivery_id`.
`not_null` on `city_code`, `delivery_date`, `status`, `payout_base_usd`, `loaded_at`.
`accepted_values` on `status`: `COMPLETED`, `RETURNED`, `CANCELLED`.
Day 5 told you *not* to put a `unique` on the header feed's business key. This day tells
you to. Both instructions are correct. Before you type it, say to yourself in one
sentence what changed — the answer is in `### The feeds`, not in the test.

**V2 — `stg_d6_delivery_adjustments`, generic.** `unique` and `not_null` on
`adjustment_id`. `not_null` on `delivery_id`, `adj_type`, `adj_amount_usd`.
`accepted_values` on `adj_type`: `TIP`, `SURGE`, `PENALTY`. `relationships` from
`delivery_id` to `stg_d6_deliveries.delivery_id`.

**V3 — mart, generic.** `not_null` on all seven columns.

**V4 — mart, intent.** No two rows of the mart share the same
(`delivery_date`, `city_code`).

**V5 — mart, intent.** Every row has `delivery_count >= 1`.

**V6 — mart, intent.** Every row has `completed_count <= delivery_count`.

**V7 — mart, intent — the reconciliation.** This is the one that matters this day, and
it is the only assertion here that compares the mart against something other than
itself. Assert, in one singular test:

> For every (`delivery_date`, `city_code`) that has at least one non-cancelled delivery
> in `stg_d6_deliveries`, the mart has exactly one row, and that row's `delivery_count`
> equals the number of such deliveries. The mart has no row for any
> (`delivery_date`, `city_code`) that has none.

Both directions. A test that only checks the pairs the mart already has cannot detect a
row the mart never wrote, and a row the mart never wrote is precisely this day's failure
mode.

**V8 — mart, intent.** `total_payout_usd` equals `payout_base_usd + adjustment_total_usd`
on every row, exactly.

V4 through V8 must be part of `dbt build`, so they run on **every** run, not just when
you remember to invoke them.

### The three runs

```bash
# Run 1 — first nightly batch. --full-refresh builds the mart from scratch.
docker compose exec dbt dbt build --select path:models/day6 --full-refresh
```

```bash
# capture the run-1 table before touching anything else
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d6_daily_city_payouts') }} order by 1,2" --limit 30
```

```bash
# Run 2 — second nightly batch, INCREMENTAL. No --full-refresh.
docker compose exec dbt dbt build --select path:models/day6 --vars '{d6_batch: 2}'
```

```bash
# capture the run-2 table
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d6_daily_city_payouts') }} order by 1,2" --limit 30
```

```bash
# Run 3 — third nightly batch, INCREMENTAL. No --full-refresh. This is the one.
docker compose exec dbt dbt build --select path:models/day6 --vars '{d6_batch: 3}'
```

```bash
# capture the run-3 table
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d6_daily_city_payouts') }} order by 1,2" --limit 30
```

### The equivalence check — run it last

An incremental model is only correct if it agrees with the model it is an optimization
of. **After** you have captured run 3's output:

```bash
docker compose exec dbt dbt build --select path:models/day6 --vars '{d6_batch: 3}' --full-refresh
```

```bash
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d6_daily_city_payouts') }} order by 1,2" --limit 30
```

This must return exactly what run 3 returned, cell for cell. It destroys the
incrementally-built table, which is why it goes last — capture run 3 first or you will be
re-running the whole protocol.

Note what this check can and cannot do. It is the only thing in the day that can catch a
row the incremental logic silently failed to touch — and it is also the reason a broken
incremental model can look healthy for weeks in production, where nobody runs it.

### Pass condition

All five of the following, or it is not a pass:

1. All three runs green — `ERROR=0`, `WARN=0`, `SKIP=0`, and the mart actually
   materialized on each.
2. Run 1's table matches the 2-row snapshot cell for cell, including column types.
3. Run 2's table matches the 7-row snapshot cell for cell, including column types.
4. Run 3's table matches the 10-row snapshot cell for cell, including column types.
5. The full-refresh rebuild matches run 3 cell for cell.

Green tests are necessary and not sufficient. At least one trap this day survives all
eight verification items; the only thing that catches it is comparing cells.

## Deliverables

```
dbt_practice/models/day6/staging/stg_d6_deliveries.sql
dbt_practice/models/day6/staging/stg_d6_delivery_adjustments.sql
dbt_practice/models/day6/staging/schema.yml
dbt_practice/models/day6/marts/fct_d6_daily_city_payouts.sql
dbt_practice/models/day6/marts/schema.yml
dbt_practice/tests/day6/          (one .sql per intent assertion — V4, V5, V6, V7, V8)
```

**Commit your models before `/review` runs.** `git add dbt_practice/models/day6
dbt_practice/tests/day6 && git commit`. This is not housekeeping: on Day 4 and again on
Day 5 the graded file was edited after execution results were visible, and both times no
pristine copy existed, so the grade had to be reconstructed from a file dump. Same
discipline as committing the verdict, applied to the solution.

Plus, in `days/day6/notes.md`:

- `## Grain plan` — **a graded deliverable, and the first thing you write.** One row per
  mart column, filled in *before* any SQL:

  | Column | Grain it is computed at | Aggregation | Filter | Comes from |
  |---|---|---|---|---|
  | `delivery_count` | one delivery | count | status <> CANCELLED | `stg_d6_deliveries` |

  Day 5's table was filled in and still put a header-level amount at the mart's grain.
  The column that decides this table is `payout_base_usd`: write the grain it is
  *computed at*, not the grain it is *published at*. Then one sentence naming, for each
  source model, how many rows of it can match a single row of the other — and what that
  means for the order you aggregate in.

- `## Watermark plan` — **also written before any SQL.** Three lines:
  1. The date, in this data, that the mart's watermark sits on at the start of run 3.
  2. The oldest `delivery_date` that run 3's batch is allowed to contain, derived from
     the SLA and the batch-3 load timestamp — not read off the seed.
  3. The gap between them, in days, and what your incremental filter therefore has to do
     about it.

- `## Assumptions` — anything you had to decide.

- `## Config decisions` — `unique_key`, `incremental_strategy`, `on_schema_change`: what
  you chose and why, plus the adapter default you are matching or overriding.

- `## Run log` — the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from all four builds, plus
  the four captured tables, pasted. Not summarized, pasted.

- `## Debrief answers` — the four questions below, in written English.

`notes.md` has now been left blank, near-blank, or stale on Days 1, 2, 3, 4 and 5. On
Day 4 the missing table was worth two defects; on Day 5 the filled sections described a
model that no longer existed. Treat it as code.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **The window.** Quote your `is_incremental()` block. Then, using the actual
   `delivery_date` values in this data: name the exact mart rows that are wrong or
   missing after run 3 if the filter is
   `where delivery_date >= (select max(delivery_date) from {{ this }})` with nothing
   subtracted. Say which of V1–V8 fire on that mart and which stay green. Then say why a
   `--full-refresh` immediately afterwards makes the same model look correct, and what
   that implies about testing incremental models in CI.

2. **Trade-off — how far back.** Your window recomputes every day inside it on every
   single run, forever. State the width you shipped and derive it from the 4-day SLA and
   the load timestamps — not from the row that happened to be late. Then: there is a
   column in the header seed that supports a *different* watermark entirely, one that
   does not need a width at all. Name it, say what that alternative buys and what it
   costs, name the one thing it needs from the mart that `delivery_date` does not, and
   give the condition under which you would ship it instead.

3. **When incremental is simply wrong.** Name a change to this mart's **business rules** —
   not its data, not its SLA — after which *no* lookback width can make the incremental
   model agree with its full-refresh equivalent. Say how you would detect that the two
   have diverged in production, where nobody is running the equivalence check by hand,
   and what a full refresh costs you at three years of deliveries.

4. **Trade-off — where the grain is enforced.** This mart folds a header feed and a line
   feed into one row. Name the failure a header-level measure suffers when the two are
   joined before either is aggregated; say which of your five measures is exposed to it
   and which is not, and why. Then explain why V7 **as specified** does not catch that
   failure, and why replacing `count(*)` with `count(distinct delivery_id)` makes the
   counts right while leaving the money wrong. Last: say what you would add to V7 to
   close the hole, what it costs on every run, and the condition under which you would
   refuse to pay it and move the check somewhere else — name where.
