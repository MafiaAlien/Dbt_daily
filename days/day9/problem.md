# dbt Daily Practice — Day 9

**Topic:** mixed-topic review — a timestamp-strategy snapshot, point-in-time attribution,
and an incremental mart over a late-arriving feed, in one DAG
**Difficulty:** Medium-Hard
**Prerequisite course:** dbt Fundamentals, Incremental Models, Snapshots / SCD (Blocks 1–3)

## Problem

A B2B SaaS company bills its customers through its own billing application. Finance wants
one table it can open every morning: **for each day and each plan, what was invoiced, what
has been collected so far against those invoices, and what is still outstanding.**

This is the review day after Block 3. Nothing in it is new. Every piece is something an
earlier day exercised: staging discipline, a snapshot, an interval join to a snapshot, a
header/line grain problem, an incremental model whose closed days reopen. This time they
sit in one DAG and feed each other, and **this brief does not repeat the warnings earlier
briefs printed.** Where a day's brief used to tell you what to watch for, this one only
states the contract.

### The feeds

- `raw_d9_customer_dump` — a **full dump** of the customer table, one per night, by
  `BATCH_ID`. Each batch has every customer that exists that night, exactly once.
  Customers are never deleted. The application overwrites records in place.
- `raw_d9_invoices` — invoice headers. **Append-only, write-once**: one row per
  `INVOICE_ID`, ever.
- `raw_d9_invoice_lines` — invoice lines. **Append-only, write-once.** One or more lines per
  invoice. Lines are loaded in the **same batch** as their invoice.
- `raw_d9_payments` — payments. **Append-only, write-once.** Zero, one or several payments
  per invoice (customers pay in installments). Payments arrive **late**.

Know what each customer column is:

| column | what it is |
|---|---|
| `CUSTOMER_ID` | the business key |
| `CUSTOMER_NAME` | the customer's legal name |
| `PLAN_CODE` | `STARTER`, `GROWTH` or `SCALE` — the plan the customer is on |
| `UPDATED_AT` | set by the billing application **on every edit of the record**, through the UI or through a script, and never otherwise. Trustworthy. |
| `BATCH_ID` | the night of the dump; plumbing, not data |

### The load schedule and the SLA

Every feed is loaded by the same nightly job. There were three loads:

| `BATCH_ID` | loaded at |
|---|---|
| 1 | `2026-09-03 02:00` |
| 2 | `2026-09-05 02:00` |
| 3 | `2026-09-06 02:00` |

- An invoice and all its lines are loaded in the **first** load after `INVOICED_AT`. They are
  never late.
- **Payment SLA:** a payment is loaded no more than **4 calendar days** after the
  `invoice_date` of the invoice it pays (`invoice_date` = the date part of `invoiced_at`).
  Nothing later ever arrives.

### Simulating three nightly runs

A var stands in for the scheduler. Copy these clauses verbatim. They are not the exercise.

`stg_d9_customers` ends with:

```sql
where batch_id = {{ var('d9_batch', 1) }}
```

`stg_d9_invoices`, `stg_d9_invoice_lines` and `stg_d9_payments` each end with:

```sql
where batch_id <= {{ var('d9_batch', 1) }}
```

The customer feed is one night's full picture, so it is read with `=`. The other three are
append-only logs, so they are read with `<=`: everything loaded up to and including that
night.

Run 1 leaves the var at its default. Run 2 passes `--vars '{d9_batch: 2}'`, run 3
`--vars '{d9_batch: 3}'`, and run 4 is a full-refresh rebuild of the mart at batch 3. Exact
commands are in `## Verification`. **All four runs are graded.**

### Layer 1 — staging (views)

All four models: rename and cast only, no filtering beyond the clause above. `batch_id` is
used by the filter and is **not** published. Each model exposes exactly the columns listed,
in that order, and **its final select lists them by name**. No `select *` anywhere in this
day's staging layer.

`stg_d9_customers` — from `raw_d9_customer_dump`. **Grain: one row per `customer_id` — 4 rows
at `d9_batch=1`, 5 at 2, 5 at 3.**

| column | type | source column |
|---|---|---|
| `customer_id` | varchar | `CUSTOMER_ID` |
| `customer_name` | varchar | `CUSTOMER_NAME` |
| `plan_code` | varchar | `PLAN_CODE` |
| `updated_at` | timestamp | `UPDATED_AT` |

`stg_d9_invoices` — from `raw_d9_invoices`. **Grain: one row per `invoice_id` — 4 / 8 / 12
rows.**

| column | type | source column |
|---|---|---|
| `invoice_id` | varchar | `INVOICE_ID` |
| `customer_id` | varchar | `CUSTOMER_ID` |
| `invoiced_at` | timestamp | `INVOICED_AT` |

`stg_d9_invoice_lines` — from `raw_d9_invoice_lines`. **Grain: one row per `line_id` — 8 / 14
/ 19 rows.**

| column | type | source column |
|---|---|---|
| `line_id` | varchar | `LINE_ID` |
| `invoice_id` | varchar | `INVOICE_ID` |
| `line_type` | varchar | `LINE_TYPE` |
| `amount_usd` | `decimal(10,2)` | `AMOUNT_USD` |

`stg_d9_payments` — from `raw_d9_payments`. **Grain: one row per `payment_id` — 2 / 7 / 12
rows.**

| column | type | source column |
|---|---|---|
| `payment_id` | varchar | `PAYMENT_ID` |
| `invoice_id` | varchar | `INVOICE_ID` |
| `paid_at` | timestamp | `PAID_AT` |
| `amount_usd` | `decimal(10,2)` | `AMOUNT_USD` |

### Layer 2 — the snapshot

`snap_d9_customers`, in `dbt_practice/snapshots/day9/`, defined in YAML (`snapshots:`).

- Its relation is `stg_d9_customers`, by `ref()`, all four columns.
- `unique_key` is `customer_id`.
- **Every edit of a customer record is a new version**, including a name correction.
- **`dbt_valid_from` must be the moment the edit was made in the billing application**, not
  the moment dbt ran. The history exists to attribute invoices, and invoice timestamps are
  application time.
- Strategy, and whatever it needs, are yours. They follow from the two bullets above. Say in
  `notes.md` what `dbt_valid_from`, `dbt_valid_to` and `dbt_updated_at` are set to under
  your choice.
- Leave `hard_deletes`, `dbt_valid_to_current` and `snapshot_meta_column_names` at their
  defaults.

A version's window is `[dbt_valid_from, dbt_valid_to)`, with `dbt_valid_to is null` meaning
open: the window extends forever. **Only the snapshot itself and `int_d9_invoice_revenue`
read from the snapshot table.**

### Layer 3 — intermediate (view, required)

#### `int_d9_invoice_revenue`

**Grain: one row per invoice** — 4 / 8 / 12 rows, one per row of `stg_d9_invoices`.

| column | type | definition |
|---|---|---|
| `invoice_id` | varchar | grain |
| `customer_id` | varchar | |
| `invoiced_at` | timestamp | |
| `invoice_date` | date | the date part of `invoiced_at` |
| `plan_code` | varchar | the customer's plan **at `invoiced_at`**: the `plan_code` of the snapshot version whose window contains `invoiced_at` |
| `billed_usd` | `decimal(12,2)` | sum of `amount_usd` over the invoice's lines |
| `collected_usd` | `decimal(12,2)` | sum of `amount_usd` over the payments loaded so far against the invoice, whatever date they were paid; `0` if there are none, never `NULL` |

### Layer 4 — mart

#### `fct_d9_daily_plan_revenue` — incremental

**Grain: one row per (`invoice_date`, `plan_code`)** that has at least one invoice. No row
for a pair with no invoices.

| column | type | definition |
|---|---|---|
| `invoice_date` | date | grain |
| `plan_code` | varchar | grain |
| `invoice_count` | integer | number of invoices with that `invoice_date`, attributed to that plan |
| `billed_usd` | `decimal(12,2)` | sum of `int_d9_invoice_revenue.billed_usd` over those invoices |
| `collected_usd` | `decimal(12,2)` | sum of `int_d9_invoice_revenue.collected_usd` over those invoices |
| `outstanding_usd` | `decimal(12,2)` | `billed_usd - collected_usd` |

The mart reads `int_d9_invoice_revenue` only. It never reads the snapshot or a staging model.

**Incremental, and the reason is the real table, not this one:** three years of invoices are
not rebuilt to add one night. `dbt_project.yml` declares `day9/marts` as `table`. The model
must be incremental anyway, and the `day9:` block is not yours to edit.

Decide and justify in `notes.md`:

- `unique_key`.
- `incremental_strategy`, **set explicitly**. Name the adapter's default and say whether you
  match it.
- `on_schema_change`, set explicitly.
- **The incremental predicate**: which rows of the int each run recomputes. It is derived
  from the SLA, and it must hold for **any** load schedule, not just the three loads above.
  A predicate tuned to pass this data is not a derivation.

On every run, the mart must equal what a full rebuild from the int would produce at that
batch. Run 4 checks exactly that.

## Input

`dbt_practice/seeds/day9/raw_d9_customer_dump.csv` — already loaded, do not edit.

```csv
CUSTOMER_ID,CUSTOMER_NAME,PLAN_CODE,UPDATED_AT,BATCH_ID
C01,Acme Robotics,STARTER,2026-08-01 10:00:00,1
C02,Birch Analytics,GROWTH,2026-07-15 09:00:00,1
C03,Cobalt Freight,SCALE,2026-06-01 12:00:00,1
C04,Delta Clinics,GROWTH,2026-08-20 16:00:00,1
C01,Acme Robotics,GROWTH,2026-09-03 14:00:00,2
C02,Birch Analytics,GROWTH,2026-07-15 09:00:00,2
C03,Cobalt Freight,SCALE,2026-06-01 12:00:00,2
C04,Delta Clinics,GROWTH,2026-08-20 16:00:00,2
C05,Ember Studio,STARTER,2026-09-04 08:00:00,2
C01,Acme Robotics,GROWTH,2026-09-03 14:00:00,3
C02,Birch Analytics Ltd,GROWTH,2026-09-05 11:00:00,3
C03,Cobalt Freight,SCALE,2026-06-01 12:00:00,3
C04,Delta Clinics,STARTER,2026-09-05 09:30:00,3
C05,Ember Studio,STARTER,2026-09-04 08:00:00,3
```

`dbt_practice/seeds/day9/raw_d9_invoices.csv` — already loaded, do not edit.

```csv
INVOICE_ID,CUSTOMER_ID,INVOICED_AT,BATCH_ID
I01,C01,2026-09-01 09:00:00,1
I02,C02,2026-09-01 15:30:00,1
I03,C03,2026-09-02 10:00:00,1
I04,C04,2026-09-02 16:45:00,1
I05,C01,2026-09-03 14:00:00,2
I06,C03,2026-09-03 11:20:00,2
I07,C05,2026-09-04 08:30:00,2
I08,C02,2026-09-04 17:10:00,2
I09,C04,2026-09-05 12:00:00,3
I10,C05,2026-09-05 10:00:00,3
I11,C01,2026-09-05 13:00:00,3
I12,C02,2026-09-05 11:00:00,3
```

`dbt_practice/seeds/day9/raw_d9_invoice_lines.csv` — already loaded, do not edit.

```csv
LINE_ID,INVOICE_ID,LINE_TYPE,AMOUNT_USD,BATCH_ID
L01,I01,SUBSCRIPTION,49.00,1
L02,I01,USAGE,12.50,1
L03,I02,SUBSCRIPTION,199.00,1
L04,I03,SUBSCRIPTION,899.00,1
L05,I03,SEATS,150.00,1
L06,I03,USAGE,37.25,1
L07,I04,SUBSCRIPTION,199.00,1
L08,I04,USAGE,20.00,1
L09,I05,SUBSCRIPTION,199.00,2
L10,I05,USAGE,5.00,2
L11,I06,USAGE,64.00,2
L12,I07,SUBSCRIPTION,49.00,2
L13,I08,SEATS,80.00,2
L14,I08,USAGE,15.75,2
L15,I09,SUBSCRIPTION,49.00,3
L16,I10,USAGE,8.40,3
L17,I11,USAGE,22.00,3
L18,I11,SEATS,40.00,3
L19,I12,USAGE,30.00,3
```

`dbt_practice/seeds/day9/raw_d9_payments.csv` — already loaded, do not edit.

```csv
PAYMENT_ID,INVOICE_ID,PAID_AT,AMOUNT_USD,BATCH_ID
P01,I01,2026-09-01 09:05:00,30.00,1
P02,I03,2026-09-02 10:30:00,500.00,1
P03,I01,2026-09-03 08:00:00,31.50,2
P04,I02,2026-09-04 12:00:00,199.00,2
P05,I05,2026-09-03 14:10:00,204.00,2
P06,I07,2026-09-04 09:00:00,25.00,2
P07,I07,2026-09-04 20:00:00,24.00,2
P08,I04,2026-09-05 16:00:00,219.00,3
P09,I03,2026-09-05 18:00:00,586.25,3
P10,I08,2026-09-05 09:00:00,95.75,3
P11,I11,2026-09-05 13:30:00,62.00,3
P12,I09,2026-09-05 12:30:00,49.00,3
```

## Expected Output

Unlike Day 8, every timestamp below is a value from `## Input`. Nothing depends on when you
ran the build, and every cell can be compared literally.

### `snap_d9_customers` after each run

Ordered by `customer_id`, then `dbt_valid_from`. `open` means `dbt_valid_to is null`. **All
three are graded.**

#### After run 1 (4 rows)

| customer_id | customer_name | plan_code | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|
| C01 | Acme Robotics | STARTER | 2026-08-01 10:00:00 | open |
| C02 | Birch Analytics | GROWTH | 2026-07-15 09:00:00 | open |
| C03 | Cobalt Freight | SCALE | 2026-06-01 12:00:00 | open |
| C04 | Delta Clinics | GROWTH | 2026-08-20 16:00:00 | open |

#### After run 2 (6 rows)

| customer_id | customer_name | plan_code | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|
| C01 | Acme Robotics | STARTER | 2026-08-01 10:00:00 | 2026-09-03 14:00:00 |
| C01 | Acme Robotics | GROWTH | 2026-09-03 14:00:00 | open |
| C02 | Birch Analytics | GROWTH | 2026-07-15 09:00:00 | open |
| C03 | Cobalt Freight | SCALE | 2026-06-01 12:00:00 | open |
| C04 | Delta Clinics | GROWTH | 2026-08-20 16:00:00 | open |
| C05 | Ember Studio | STARTER | 2026-09-04 08:00:00 | open |

#### After run 3 (8 rows)

| customer_id | customer_name | plan_code | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|
| C01 | Acme Robotics | STARTER | 2026-08-01 10:00:00 | 2026-09-03 14:00:00 |
| C01 | Acme Robotics | GROWTH | 2026-09-03 14:00:00 | open |
| C02 | Birch Analytics | GROWTH | 2026-07-15 09:00:00 | 2026-09-05 11:00:00 |
| C02 | Birch Analytics Ltd | GROWTH | 2026-09-05 11:00:00 | open |
| C03 | Cobalt Freight | SCALE | 2026-06-01 12:00:00 | open |
| C04 | Delta Clinics | GROWTH | 2026-08-20 16:00:00 | 2026-09-05 09:30:00 |
| C04 | Delta Clinics | STARTER | 2026-09-05 09:30:00 | open |
| C05 | Ember Studio | STARTER | 2026-09-04 08:00:00 | open |

### `int_d9_invoice_revenue` after run 3 (12 rows)

Ordered by `invoice_id`.

| invoice_id | customer_id | invoiced_at | invoice_date | plan_code | billed_usd | collected_usd |
|---|---|---|---|---|---|---|
| I01 | C01 | 2026-09-01 09:00:00 | 2026-09-01 | STARTER | 61.50 | 61.50 |
| I02 | C02 | 2026-09-01 15:30:00 | 2026-09-01 | GROWTH | 199.00 | 199.00 |
| I03 | C03 | 2026-09-02 10:00:00 | 2026-09-02 | SCALE | 1086.25 | 1086.25 |
| I04 | C04 | 2026-09-02 16:45:00 | 2026-09-02 | GROWTH | 219.00 | 219.00 |
| I05 | C01 | 2026-09-03 14:00:00 | 2026-09-03 | GROWTH | 204.00 | 204.00 |
| I06 | C03 | 2026-09-03 11:20:00 | 2026-09-03 | SCALE | 64.00 | 0.00 |
| I07 | C05 | 2026-09-04 08:30:00 | 2026-09-04 | STARTER | 49.00 | 49.00 |
| I08 | C02 | 2026-09-04 17:10:00 | 2026-09-04 | GROWTH | 95.75 | 95.75 |
| I09 | C04 | 2026-09-05 12:00:00 | 2026-09-05 | STARTER | 49.00 | 49.00 |
| I10 | C05 | 2026-09-05 10:00:00 | 2026-09-05 | STARTER | 8.40 | 0.00 |
| I11 | C01 | 2026-09-05 13:00:00 | 2026-09-05 | GROWTH | 62.00 | 62.00 |
| I12 | C02 | 2026-09-05 11:00:00 | 2026-09-05 | GROWTH | 30.00 | 0.00 |

### `fct_d9_daily_plan_revenue` after each run

Ordered by `invoice_date`, then `plan_code`. **All four are graded.**

#### After run 1 (4 rows)

| invoice_date | plan_code | invoice_count | billed_usd | collected_usd | outstanding_usd |
|---|---|---|---|---|---|
| 2026-09-01 | GROWTH | 1 | 199.00 | 0.00 | 199.00 |
| 2026-09-01 | STARTER | 1 | 61.50 | 30.00 | 31.50 |
| 2026-09-02 | GROWTH | 1 | 219.00 | 0.00 | 219.00 |
| 2026-09-02 | SCALE | 1 | 1086.25 | 500.00 | 586.25 |

#### After run 2 (8 rows)

| invoice_date | plan_code | invoice_count | billed_usd | collected_usd | outstanding_usd |
|---|---|---|---|---|---|
| 2026-09-01 | GROWTH | 1 | 199.00 | 199.00 | 0.00 |
| 2026-09-01 | STARTER | 1 | 61.50 | 61.50 | 0.00 |
| 2026-09-02 | GROWTH | 1 | 219.00 | 0.00 | 219.00 |
| 2026-09-02 | SCALE | 1 | 1086.25 | 500.00 | 586.25 |
| 2026-09-03 | GROWTH | 1 | 204.00 | 204.00 | 0.00 |
| 2026-09-03 | SCALE | 1 | 64.00 | 0.00 | 64.00 |
| 2026-09-04 | GROWTH | 1 | 95.75 | 0.00 | 95.75 |
| 2026-09-04 | STARTER | 1 | 49.00 | 49.00 | 0.00 |

#### After run 3 (10 rows) — and after run 4, identical

| invoice_date | plan_code | invoice_count | billed_usd | collected_usd | outstanding_usd |
|---|---|---|---|---|---|
| 2026-09-01 | GROWTH | 1 | 199.00 | 199.00 | 0.00 |
| 2026-09-01 | STARTER | 1 | 61.50 | 61.50 | 0.00 |
| 2026-09-02 | GROWTH | 1 | 219.00 | 219.00 | 0.00 |
| 2026-09-02 | SCALE | 1 | 1086.25 | 1086.25 | 0.00 |
| 2026-09-03 | GROWTH | 1 | 204.00 | 204.00 | 0.00 |
| 2026-09-03 | SCALE | 1 | 64.00 | 0.00 | 64.00 |
| 2026-09-04 | GROWTH | 1 | 95.75 | 95.75 | 0.00 |
| 2026-09-04 | STARTER | 1 | 49.00 | 49.00 | 0.00 |
| 2026-09-05 | GROWTH | 2 | 92.00 | 62.00 | 30.00 |
| 2026-09-05 | STARTER | 2 | 57.40 | 49.00 | 8.40 |

After run 3: `sum(invoice_count)` is **12**, `sum(billed_usd)` is **2127.90**, the sum of
every line, and `sum(collected_usd)` is **2025.50**, the sum of every payment.

**Before you write the mart, reconcile the three mart tables against each other in
writing**: for each cell that changes between run 1 and run 2, and between run 2 and run 3,
name the input row that changed it and the batch it arrived in. That list goes in
`## Plan` part 3. It is the derivation your incremental predicate has to survive.

## Verification

### Tests you must write

**No packages.** Anything the four built-in generic tests cannot express is a **singular
test** in `dbt_practice/tests/day9/`, one file per assertion, named after what it asserts.

**V1 — `stg_d9_customers`, generic.** `unique` and `not_null` on `customer_id`. `not_null` on
`customer_name`, `plan_code`, `updated_at`. `accepted_values` on `plan_code`: `STARTER`,
`GROWTH`, `SCALE`.

**V2 — `stg_d9_invoices`, generic.** `unique` and `not_null` on `invoice_id`. `not_null` on
`customer_id`, `invoiced_at`. `relationships` from `customer_id` to
`stg_d9_customers.customer_id`.

**V3 — `stg_d9_invoice_lines`, generic.** `unique` and `not_null` on `line_id`. `not_null` on
`invoice_id`, `amount_usd`. `accepted_values` on `line_type`: `SUBSCRIPTION`, `USAGE`,
`SEATS`. `relationships` from `invoice_id` to `stg_d9_invoices.invoice_id`.

**V4 — `stg_d9_payments`, generic.** `unique` and `not_null` on `payment_id`. `not_null` on
`invoice_id`, `paid_at`, `amount_usd`. `relationships` from `invoice_id` to
`stg_d9_invoices.invoice_id`.

**V5 — the snapshot, generic, in its YAML.** `not_null` on `customer_id`, `plan_code`,
`dbt_valid_from`.

**V6 — the snapshot, intent: the versions of each customer tile its timeline.** For every
`customer_id`: exactly one open version; every closed version's `dbt_valid_to` is the
`dbt_valid_from` of that customer's next version (no gap, no overlap); no window is empty.
One assertion, one file.

**V7 — `int_d9_invoice_revenue`, generic.** `unique` and `not_null` on `invoice_id`.
`not_null` on `invoice_date`, `plan_code`, `billed_usd`, `collected_usd`. `accepted_values`
on `plan_code`: `STARTER`, `GROWTH`, `SCALE`.

**V8 — int, intent: reconciliation against `stg_d9_invoices`.** Both directions: every
invoice in staging is in the int exactly once, and the int has no invoice that staging does
not. You have written this test on three previous days. The shape is not printed this time.

**V9 — int, intent: attribution, derived independently.** For every invoice, the int's
`plan_code` equals the plan of the customer's version **with the greatest `dbt_valid_from`
not after `invoiced_at`**. Write it **without reading `dbt_valid_to`**. A test that reuses the
model's join predicate inherits the model's bug, which was Day 7's V10. This one reaches the
same answer by a different route, so the two can disagree.

**V10 — `fct_d9_daily_plan_revenue`, generic.** `not_null` on `invoice_date`, `plan_code`,
`invoice_count`, `billed_usd`, `collected_usd`, `outstanding_usd`. `accepted_values` on
`plan_code`: `STARTER`, `GROWTH`, `SCALE`.

**V11 — mart, intent: the grain.** No two rows share (`invoice_date`, `plan_code`).

**V12 — mart, intent: totals tie out to staging.** `sum(invoice_count)` equals the row count
of `stg_d9_invoices`; `sum(billed_usd)` equals the sum of `stg_d9_invoice_lines.amount_usd`;
`sum(collected_usd)` equals the sum of `stg_d9_payments.amount_usd`. It reads **staging**,
not the int. Say in `notes.md` why.

V6, V8, V9, V11 and V12 must be part of `dbt build`, so they run on **every** run.

### Prove each intent test can fire, in both directions

Days 7 and 8 shipped intent tests that could never be red and one that could never be green.
The rule from Day 8's digest has two halves, and this day grades both:

- **Red on deliberately broken input.** For **V8, V9 and V12**, make one temporary change to
  your own model that each test exists to catch. Build, and paste the `FAIL n` line. Then
  revert. The change is yours to choose; write down what it was.
- **Green on known-correct input.** That is what runs 1–4 are.

Record both in `## Red proof`. A test without its red line is graded as not written.

### Count your tests before you trust them

Count the assertions V1–V12 ask for and write the number into `notes.md` **before run 1**.
Then compare it with:

```bash
docker compose exec dbt dbt ls --resource-type test --select path:models/day9 path:snapshots/day9 path:tests/day9 --quiet
```

### Starting over

The snapshot **and** the incremental mart both accumulate across runs. To restart the
protocol (wrong order, a run repeated, a config you want to change after run 1), drop
both, then start again at run 1:

```bash
docker compose exec dbt python3 -c "import duckdb; c = duckdb.connect('/workspace/practice.duckdb'); c.execute('drop table if exists main.snap_d9_customers'); c.execute('drop table if exists main.fct_d9_daily_plan_revenue')"
```

### One warning that is not yours

Until your first model exists under each of `day9/staging/`, `day9/intermediate/` and
`day9/marts/`, every dbt command prints a `Configuration paths exist in your
dbt_project.yml file which do not apply to any resources` warning naming the empty ones.
It does not count in `WARN=`, and the `day9:` block is not yours to edit.

### The four runs

```bash
# Run 1 — first nightly load.
docker compose exec dbt dbt build --select path:models/day9 path:snapshots/day9 path:tests/day9
```

```bash
# Run 2 — second nightly load.
docker compose exec dbt dbt build --select path:models/day9 path:snapshots/day9 path:tests/day9 --vars '{d9_batch: 2}'
```

```bash
# Run 3 — third nightly load.
docker compose exec dbt dbt build --select path:models/day9 path:snapshots/day9 path:tests/day9 --vars '{d9_batch: 3}'
```

```bash
# Run 4 — rebuild the mart from scratch at batch 3. Must equal run 3, cell for cell.
docker compose exec dbt dbt build --select fct_d9_daily_plan_revenue --full-refresh --vars '{d9_batch: 3}'
```

Captures. Run the snapshot capture and the mart capture after **every** run; the int and the
column types after run 3.

```bash
# capture the snapshot
docker compose exec dbt dbt show --inline "select customer_id, customer_name, plan_code, dbt_valid_from, dbt_valid_to from {{ ref('snap_d9_customers') }} order by customer_id, dbt_valid_from" --limit 30
```

```bash
# capture the mart
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d9_daily_plan_revenue') }} order by invoice_date, plan_code" --limit 30
```

```bash
# capture the int (after run 3; customer_id omitted to fit dbt show's width)
docker compose exec dbt dbt show --inline "select invoice_id, invoiced_at, invoice_date, plan_code, billed_usd, collected_usd from {{ ref('int_d9_invoice_revenue') }} order by invoice_id" --limit 30
```

```bash
# capture column types of the int and the mart (after run 3)
docker compose exec dbt dbt show --inline "select table_name, column_name, data_type from information_schema.columns where table_name in ('int_d9_invoice_revenue', 'fct_d9_daily_plan_revenue') order by table_name, ordinal_position" --limit 30
```

Do **not** pass `--full-refresh` anywhere except run 4.

### Pass condition

All seven, or it is not a pass:

1. All four builds green: `ERROR=0`, `WARN=0`, `SKIP=0`; the snapshot actually ran on runs
   1–3 (`OK snapshotted`).
2. The test count from `dbt ls` equals the number of assertions V1–V12 ask for.
3. The snapshot matches the 4-row, 6-row and 8-row tables cell for cell.
4. `int_d9_invoice_revenue` matches its 12-row table cell for cell, including column types.
5. The mart matches the 4-row, 8-row and 10-row tables cell for cell after runs 1, 2 and 3,
   including `integer` for `invoice_count` and `decimal(12,2)` for the three amounts.
6. Run 4's mart is identical to run 3's.
7. `## Red proof` has a `FAIL` line for each of V8, V9 and V12.

Green tests are necessary and not sufficient. Compare cells.

## Deliverables

```
dbt_practice/models/day9/staging/stg_d9_customers.sql
dbt_practice/models/day9/staging/stg_d9_invoices.sql
dbt_practice/models/day9/staging/stg_d9_invoice_lines.sql
dbt_practice/models/day9/staging/stg_d9_payments.sql
dbt_practice/models/day9/staging/schema.yml
dbt_practice/snapshots/day9/snap_d9_customers.yml
dbt_practice/models/day9/intermediate/int_d9_invoice_revenue.sql
dbt_practice/models/day9/intermediate/schema.yml
dbt_practice/models/day9/marts/fct_d9_daily_plan_revenue.sql
dbt_practice/models/day9/marts/schema.yml
dbt_practice/tests/day9/          (one .sql per intent assertion — V6, V8, V9, V11, V12)
```

**Two commits, in this order.** The first comes before any SQL exists. Eight days of
`notes.md` have been blank, and on the last three the blank line was the defect that survived.
So the plan is now a commit of its own, and `/review` checks that it comes first:

```bash
# 1. Before any file under dbt_practice/models/day9 exists — notes.md with ## Plan filled in.
git add days/day9/notes.md && git commit -m "Day 9 plan"
```

```bash
# 2. After you have seen all four runs green — before /genprompt.
git add dbt_practice/models/day9 dbt_practice/snapshots/day9 dbt_practice/tests/day9 days/day9/notes.md && git commit -m "Day 9 as submitted"
```

**Submit only a solution you have seen build.** That has been missed three times (Days 1, 7
and 8). Paste the final `Done.` line of each of the four runs into `## Run log` *before*
commit 2. If there is no green line to paste, do not make the commit. And if the error is
in the environment rather than in your models, raise it.

Plus, in `days/day9/notes.md`:

- `## Plan` — **graded, committed alone in commit 1, before any SQL.** Three parts:
  1. **Grain.** For each column of `int_d9_invoice_revenue`: which relation it is read
     from, and the grain at which it is computed. Then, for each relation the int reads,
     the answer to the question Day 6 and Day 7 asked and never got answered: *how many rows
     of it can match one invoice?*
  2. **Attribution.** The join predicate from an invoice to a snapshot version, as SQL. Then
     for each of the 12 invoices, the version it matches after run 3, named by
     `customer_id` and `dbt_valid_from`.
  3. **Watermark.** The oldest `invoice_date` a nightly load can legally carry a payment
     for, as an expression in the mart's current `max(invoice_date)`, derived from the SLA
     for **any** load schedule. Then the oldest date runs 2 and 3 actually need to
     recompute on this data, from the reconciliation asked for under `## Expected Output`.
- `## Config decisions` — the snapshot strategy and every key you set, and what
  `dbt_valid_from` / `dbt_valid_to` / `dbt_updated_at` become under it. The mart's
  `unique_key`, `incremental_strategy` (and the adapter default), `on_schema_change`, and
  where each is set.
- `## Test count` — the number of assertions V1–V12 ask for, the `dbt ls` number, and what
  the difference was if they ever differed.
- `## Red proof` — for each of V8, V9, V12: the temporary change, the pasted `FAIL n` line,
  and confirmation it was reverted.
- `## Assumptions` — anything you had to decide.
- `## Run log` — the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from all four builds, and
  every captured table, **pasted, not summarized.**
- `## Debrief answers` — the four questions below, in written English.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **Trade-off: the lookback window.** State your incremental predicate and derive it from
   the SLA in one line of arithmetic. Then: (a) on this data, what is the smallest lookback
   that still produces the expected tables, and why is choosing it wrong? (b) Batches start
   running every 6 hours instead of nightly. Does your predicate change? (c) The
   alternative is to recompute only the `invoice_date`s touched by the payment rows that
   arrived in the latest load. Say what that needs that this day's contract does not give
   you, what it saves on three years of history, and when you would switch to it.

2. **Trade-off: `unique_key` and the strategy.** You chose a `unique_key` and an
   `incremental_strategy`. Construct one change to `## Input`, a single row edited or
   added, under which `unique_key = ['invoice_date', 'plan_code']` and `unique_key =
   'invoice_date'` produce **different** marts under `delete+insert`. Say which mart is
   right, and why the wrong one still passes V11. Then say what `merge` would have done
   with the same row.

3. **Snapshot strategy.** C02's name correction created a version that no invoice
   attribution needed. (a) Under your strategy, why could you not avoid it, and what does
   it cost downstream? (b) Name the config that would have avoided it, and for each of the
   12 invoices say whether its `plan_code` would still be right, and why. Look at how
   `dbt_valid_from` would be set. (c) When would you accept that cost and use it anyway?

4. **Tests that read the right parent.** V12 reads staging, not the int, and V9 may not
   read `dbt_valid_to`. Both rules come from the same principle. State it in one sentence.
   Then name one defect this day's pipeline could have that a tie-out against the **int**
   would not catch, and say which of your tests does catch it.
