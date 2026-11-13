# dbt Daily Practice — Day 10

**Topic:** Jinja loops that generate repetitive conditional-aggregation SQL — `{% for %}` over
a project var, `loop.last`, whitespace control, and reading the compiled SQL (the dbt version
of the PySpark pivot drills)
**Difficulty:** Medium
**Prerequisite course:** Jinja, Macros & Packages

## Problem

A marketplace takes payments for its merchants' orders. Finance wants one row per merchant per
month that breaks the captured money down by payment method, with one pair of columns per
method: how many orders used it, and how much was captured through it.

The list of methods that get their own columns is a business decision. It changes, and when
it does nobody wants to edit SQL. It lives in **one place**, the project var
`d10_payment_methods`, which is already declared in `dbt_practice/dbt_project.yml`:

```yaml
vars:
  d10_payment_methods: ['card', 'wallet', 'bank_transfer']
```

Every column that depends on a method is generated from that list by a Jinja loop. Run 2 below
adds a method on the command line, and the mart and its tests must follow **with no file
edited**.

**No packages.** `dbt_utils.pivot`, `dbt_utils.get_column_values`, `dbt_expectations` and
everything else under `dbt_packages/` are off-limits. The loop is today's exercise, so write it
yourself. Anything the four built-in generic tests cannot express is a **singular test** in
`dbt_practice/tests/day10/`.

### The feeds

The seeds are already in `dbt_practice/seeds/day10/` and loaded. Do not edit them.

- `raw_d10_orders`: one row per order. `ordered_at` is when the order was placed.
- `raw_d10_payments`: one row per payment attempt against an order. An order can have several
  payments, of the same method or of different ones. Split tender and instalments both
  happen. `status` is `captured` (the money moved) or `failed` (it did not). The source
  system's `payment_method` casing is inconsistent, and some payments were recorded with no
  method at all.

### Layer 1 — staging (views)

Explicit column lists with explicit casts. **No `select *`, anywhere in the day.** That has
been forbidden by name twice and has still appeared four times (Days 2, 7, 8, 9). No column
appears in a model's output unless the contract below lists it.

#### `stg_d10_orders`

| column | type | rule |
|---|---|---|
| `order_id` | VARCHAR | as is |
| `merchant_id` | VARCHAR | as is |
| `ordered_at` | TIMESTAMP | as is |

#### `stg_d10_payments`

| column | type | rule |
|---|---|---|
| `payment_id` | VARCHAR | as is |
| `order_id` | VARCHAR | as is |
| `payment_method` | VARCHAR | lower-cased; a payment recorded without a method keeps a missing method (staging does not invent values) |
| `status` | VARCHAR | as is |
| `amount_usd` | DECIMAL(10,2) | as is |
| `paid_at` | TIMESTAMP | as is |

### Layer 2 — intermediate (view, required)

#### `int_d10_captured_payments`

One row per **captured** payment, carrying the merchant and month of the order it pays for.

| column | type | rule |
|---|---|---|
| `payment_id` | VARCHAR | from `stg_d10_payments` |
| `order_id` | VARCHAR | from `stg_d10_payments` |
| `merchant_id` | VARCHAR | the order's merchant |
| `order_month` | DATE | first day of the month of the order's `ordered_at`, **not** of `paid_at` |
| `payment_method` | VARCHAR | from `stg_d10_payments` |
| `amount_usd` | DECIMAL(10,2) | from `stg_d10_payments` |

### Layer 3 — mart (table)

#### `fct_d10_merchant_month_payments`

**Grain:** one row per (`merchant_id`, `order_month`) in which the merchant had at least one
order placed. `order_month` is the first day of the month of `ordered_at`. A merchant-month
with orders but no captured money still has a row.

Every payment metric is attributed to the **order's** month, whatever the payment's
`paid_at`. "Captured payment" means `status = 'captured'`, and no other payment counts in any
metric below.

Columns, in this order. `{m}` stands for each method in `var('d10_payment_methods')`, taken in
list order. For each `{m}`, `{m}_order_count` comes first and `{m}_amount_usd` second:

| column | type | definition |
|---|---|---|
| `merchant_id` | VARCHAR | |
| `order_month` | DATE | |
| `order_count` | INTEGER | number of orders placed in the merchant-month, whatever their payments |
| `captured_amount_usd` | DECIMAL(12,2) | sum of `amount_usd` over captured payments of the merchant-month's orders; `0.00` when there are none |
| `{m}_order_count` | INTEGER | number of orders in the merchant-month with at least one captured payment whose method is `{m}` |
| `{m}_amount_usd` | DECIMAL(12,2) | sum of `amount_usd` over captured payments whose method is `{m}`, for the merchant-month's orders; `0.00` when there are none |
| `other_order_count` | INTEGER | number of orders in the merchant-month with at least one captured payment whose method is not one of the methods in `d10_payment_methods` |
| `other_amount_usd` | DECIMAL(12,2) | sum of `amount_usd` over captured payments whose method is not one of the methods in `d10_payment_methods`, for the merchant-month's orders; `0.00` when there are none |

Under the default var, run 1 publishes 12 columns. Under run 2's var it publishes 14.

The method names appear in **no** `.sql` file you write, whether model or test. The literal
`'card'` typed into a model is the thing this day exists to remove. The pass condition greps
for it.

## Input

`dbt_practice/seeds/day10/raw_d10_orders.csv` — already loaded, do not edit.

```csv
order_id,merchant_id,ordered_at
O01,M1,2026-09-03 10:15:00
O02,M1,2026-09-14 16:40:00
O03,M1,2026-09-29 23:50:00
O04,M2,2026-09-05 09:00:00
O05,M2,2026-09-20 12:30:00
O06,M1,2026-10-02 08:20:00
O07,M1,2026-10-11 19:05:00
O08,M2,2026-10-07 14:10:00
O09,M2,2026-10-18 11:45:00
O10,M2,2026-10-25 17:30:00
O11,M3,2026-10-09 10:00:00
O12,M3,2026-10-30 21:15:00
O13,M3,2026-09-22 13:05:00
```

`dbt_practice/seeds/day10/raw_d10_payments.csv` — already loaded, do not edit.

```csv
payment_id,order_id,payment_method,status,amount_usd,paid_at
P01,O01,card,captured,40.00,2026-09-03 10:16:00
P02,O01,card,captured,25.50,2026-09-03 10:17:30
P03,O02,CARD,failed,80.00,2026-09-14 16:41:00
P04,O02,wallet,captured,80.00,2026-09-14 16:43:00
P05,O03,Wallet,captured,30.00,2026-10-01 00:05:00
P06,O03,,captured,12.00,2026-10-01 00:06:00
P07,O04,bank_transfer,captured,150.00,2026-09-06 09:00:00
P08,O05,card,failed,45.00,2026-09-20 12:31:00
P09,O06,bnpl,captured,120.00,2026-10-02 08:21:00
P10,O06,card,captured,20.00,2026-10-02 08:22:00
P11,O07,card,captured,60.00,2026-10-11 19:06:00
P12,O08,gift_card,captured,25.00,2026-10-07 14:11:00
P13,O08,card,captured,35.00,2026-10-07 14:11:30
P14,O09,BNPL,captured,60.00,2026-10-18 11:46:00
P15,O09,bnpl,captured,30.00,2026-11-18 11:46:00
P16,O10,wallet,failed,55.00,2026-10-25 17:31:00
P17,O10,wallet,captured,55.00,2026-10-25 17:33:00
P18,O11,,captured,18.00,2026-10-09 10:01:00
P19,O11,bank_transfer,captured,200.00,2026-10-09 10:02:00
P20,O13,wallet,failed,70.00,2026-09-22 13:06:00
```

## Expected Output

Comparison is order-insensitive. Rows are shown sorted by `order_month`, then `merchant_id`.
Every cell and every column type must match. A missing value is written `(null)`.

### `int_d10_captured_payments` (16 rows, both runs)

| payment_id | order_id | merchant_id | order_month | payment_method | amount_usd |
|---|---|---|---|---|---|
| P01 | O01 | M1 | 2026-09-01 | card | 40.00 |
| P02 | O01 | M1 | 2026-09-01 | card | 25.50 |
| P04 | O02 | M1 | 2026-09-01 | wallet | 80.00 |
| P05 | O03 | M1 | 2026-09-01 | wallet | 30.00 |
| P06 | O03 | M1 | 2026-09-01 | (null) | 12.00 |
| P07 | O04 | M2 | 2026-09-01 | bank_transfer | 150.00 |
| P09 | O06 | M1 | 2026-10-01 | bnpl | 120.00 |
| P10 | O06 | M1 | 2026-10-01 | card | 20.00 |
| P11 | O07 | M1 | 2026-10-01 | card | 60.00 |
| P12 | O08 | M2 | 2026-10-01 | gift_card | 25.00 |
| P13 | O08 | M2 | 2026-10-01 | card | 35.00 |
| P14 | O09 | M2 | 2026-10-01 | bnpl | 60.00 |
| P15 | O09 | M2 | 2026-10-01 | bnpl | 30.00 |
| P17 | O10 | M2 | 2026-10-01 | wallet | 55.00 |
| P18 | O11 | M3 | 2026-10-01 | (null) | 18.00 |
| P19 | O11 | M3 | 2026-10-01 | bank_transfer | 200.00 |

### `fct_d10_merchant_month_payments` after run 1 (6 rows, 12 columns)

`d10_payment_methods = ['card', 'wallet', 'bank_transfer']`

| merchant_id | order_month | order_count | captured_amount_usd | card_order_count | card_amount_usd | wallet_order_count | wallet_amount_usd | bank_transfer_order_count | bank_transfer_amount_usd | other_order_count | other_amount_usd |
|---|---|---|---|---|---|---|---|---|---|---|---|
| M1 | 2026-09-01 | 3 | 187.50 | 1 | 65.50 | 2 | 110.00 | 0 | 0.00 | 1 | 12.00 |
| M2 | 2026-09-01 | 2 | 150.00 | 0 | 0.00 | 0 | 0.00 | 1 | 150.00 | 0 | 0.00 |
| M3 | 2026-09-01 | 1 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 | 0.00 |
| M1 | 2026-10-01 | 2 | 200.00 | 2 | 80.00 | 0 | 0.00 | 0 | 0.00 | 1 | 120.00 |
| M2 | 2026-10-01 | 3 | 205.00 | 1 | 35.00 | 1 | 55.00 | 0 | 0.00 | 2 | 115.00 |
| M3 | 2026-10-01 | 2 | 218.00 | 0 | 0.00 | 0 | 0.00 | 1 | 200.00 | 1 | 18.00 |

### `fct_d10_merchant_month_payments` after run 2 (6 rows, 14 columns)

`d10_payment_methods = ['card', 'wallet', 'bank_transfer', 'bnpl']`

| merchant_id | order_month | order_count | captured_amount_usd | card_order_count | card_amount_usd | wallet_order_count | wallet_amount_usd | bank_transfer_order_count | bank_transfer_amount_usd | bnpl_order_count | bnpl_amount_usd | other_order_count | other_amount_usd |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M1 | 2026-09-01 | 3 | 187.50 | 1 | 65.50 | 2 | 110.00 | 0 | 0.00 | 0 | 0.00 | 1 | 12.00 |
| M2 | 2026-09-01 | 2 | 150.00 | 0 | 0.00 | 0 | 0.00 | 1 | 150.00 | 0 | 0.00 | 0 | 0.00 |
| M3 | 2026-09-01 | 1 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 | 0.00 | 0 | 0.00 |
| M1 | 2026-10-01 | 2 | 200.00 | 2 | 80.00 | 0 | 0.00 | 0 | 0.00 | 1 | 120.00 | 0 | 0.00 |
| M2 | 2026-10-01 | 3 | 205.00 | 1 | 35.00 | 1 | 55.00 | 0 | 0.00 | 1 | 90.00 | 1 | 25.00 |
| M3 | 2026-10-01 | 2 | 218.00 | 0 | 0.00 | 0 | 0.00 | 1 | 200.00 | 0 | 0.00 | 1 | 18.00 |

### Column types

| relation | column | type |
|---|---|---|
| int | `payment_id`, `order_id`, `merchant_id`, `payment_method` | VARCHAR |
| int | `order_month` | DATE |
| int | `amount_usd` | DECIMAL(10,2) |
| mart | `merchant_id` | VARCHAR |
| mart | `order_month` | DATE |
| mart | `order_count` and every `*_order_count` | INTEGER (the capture below prints it as `int32`) |
| mart | `captured_amount_usd` and every `*_amount_usd` | DECIMAL(12,2) |

## Verification

### Tests you must write

**V1 — `stg_d10_orders`, generic.** `unique` and `not_null` on `order_id`. `not_null` on
`merchant_id`, `ordered_at`.

**V2 — `stg_d10_payments`, generic.** `unique` and `not_null` on `payment_id`. `not_null` on
`order_id`, `status`, `amount_usd`. `accepted_values` on `status`: `captured`, `failed`.
`relationships` from `order_id` to `stg_d10_orders.order_id`.

**V3 — `int_d10_captured_payments`, generic.** `unique` and `not_null` on `payment_id`.
`not_null` on `order_id`, `merchant_id`, `order_month`, `amount_usd`.

**V4 — `fct_d10_merchant_month_payments`, generic.** `not_null` on `merchant_id`,
`order_month`, `order_count`, `captured_amount_usd`. These four columns are fixed, and they are
the only mart columns that get generic tests in `schema.yml`. The generated columns are
covered by V5 and V6.

**V5 — mart, intent: every generated column is populated.** For every method in
`var('d10_payment_methods')`, and for `other`: `{m}_order_count` and `{m}_amount_usd` are not
null and not negative, on every row. One singular test, one file, written as a loop over the
var. When run 2 adds a method, V5 covers its two columns with no edit.

**V6 — mart, intent: the methods partition the money.** On every row, the sum of every
`{m}_amount_usd` plus `other_amount_usd` equals `captured_amount_usd`. One singular test,
generated from the same var.

**V7 — mart, intent: the grain.** No two rows share (`merchant_id`, `order_month`).

**V8 — mart, intent: totals tie out to staging.** `sum(order_count)` equals the row count of
`stg_d10_orders`, and `sum(captured_amount_usd)` equals the sum of `amount_usd` over captured
payments in `stg_d10_payments`. It reads **staging**, not the int. Say in `notes.md` why.

V5–V8 must be part of `dbt build`, so they run on **both** runs.

### Prove each intent test can fire

Two days running, an intent test has shipped that could never be red or never be green (Day 8's
V12, Day 9's V9). This day grades both halves again:

- **Red on deliberately broken input.** For **V5, V6 and V8**, make one temporary change to
  your own model that each test exists to catch. Build, and paste the `FAIL n` line. Then
  revert. The change is yours to choose; write down what it was.
- **Green on known-correct input.** That is what runs 1 and 2 are.

Record both in `## Red proof`. A test without its red line is graded as not written.

### Count your tests before you trust them

Count the assertions V1–V8 ask for and write the number into `notes.md` **before run 1**. Then
compare it with:

```bash
docker compose exec dbt dbt ls --resource-type test --select path:models/day10 path:tests/day10 --quiet
```

A test that `dbt ls` does not list does not run, however green the build is. That was Day 6's
`schema.yml` typo, Day 7's V9, and Day 9's V12.

### Warnings that are not yours to fix today

- Until your first model exists under each of `day10/staging/`, `day10/intermediate/` and
  `day10/marts/`, every dbt command prints `Configuration paths exist in your dbt_project.yml
  file which do not apply to any resources`, naming the empty ones. It does not count in
  `WARN=`, and the `day10:` block is not yours to edit.
- Every dbt command currently prints two parse WARNINGs about `tests/day7/test_fct_reconciliation.sql`
  and `tests/day9/test_usd_stg_fct.sql`, each depending on a model that does not exist. They
  are earlier days' graded artifacts, so leave them as they are. They are outside today's
  selection.

### The two runs

```bash
# Run 1 — the default method list from dbt_project.yml.
docker compose exec dbt dbt build --select path:models/day10 path:tests/day10
```

```bash
# Run 2 — finance gives bnpl its own columns. No file is edited between run 1 and run 2.
docker compose exec dbt dbt build --select path:models/day10 path:tests/day10 --vars '{d10_payment_methods: [card, wallet, bank_transfer, bnpl]}'
```

If any file has to change after run 1, start again at run 1.

Captures. Run the mart capture after **each** run, and the int capture once. The header rows
print each column's type, so the type check needs no separate command.

```bash
# capture the mart
docker compose exec dbt python3 -c "import duckdb; c = duckdb.connect('/workspace/practice.duckdb', read_only=True); c.sql('select * from main.fct_d10_merchant_month_payments order by order_month, merchant_id').show(max_width=10000)"
```

```bash
# capture the int
docker compose exec dbt python3 -c "import duckdb; c = duckdb.connect('/workspace/practice.duckdb', read_only=True); c.sql('select * from main.int_d10_captured_payments order by order_month, merchant_id, payment_id').show(max_width=10000)"
```

```bash
# capture the mart's compiled SQL — immediately after run 2, before any other dbt command
cat dbt_practice/target/compiled/dbt_practice/models/day10/marts/fct_d10_merchant_month_payments.sql
```

```bash
# the one-place check — must print nothing
grep -rnE "'(card|wallet|bank_transfer|bnpl)'" dbt_practice/models/day10 dbt_practice/tests/day10
```

### Pass condition

1. Run 1: `ERROR=0 WARN=0`, and the number of tests that ran equals your count.
2. The mart after run 1 matches its Expected Output table: 6 rows, 12 columns, every cell and
   type.
3. Run 2: `ERROR=0 WARN=0`, with no file edited since run 1.
4. The mart after run 2 matches its Expected Output table: 6 rows, 14 columns, every cell and
   type.
5. The int matches its Expected Output table, every cell and type.
6. The one-place `grep` prints nothing, and the compiled SQL from run 2 contains the
   `bnpl_order_count` and `bnpl_amount_usd` expressions.
7. `## Red proof` has a `FAIL n` line for each of V5, V6, V8.

## Deliverables

```
dbt_practice/models/day10/staging/stg_d10_orders.sql
dbt_practice/models/day10/staging/stg_d10_payments.sql
dbt_practice/models/day10/staging/schema.yml
dbt_practice/models/day10/intermediate/int_d10_captured_payments.sql
dbt_practice/models/day10/intermediate/schema.yml
dbt_practice/models/day10/marts/fct_d10_merchant_month_payments.sql
dbt_practice/models/day10/marts/schema.yml
dbt_practice/tests/day10/          (one .sql per intent assertion — V5, V6, V7, V8)
```

**How `notes.md` works.** Every line in `days/day10/notes.md` that starts with `## ` is a
Markdown section heading. It is not a tag. Write your answer on the lines below it, before the
next `## `. Each heading matches one bullet at the end of this section, and that bullet says
what goes under it. Under each heading there is a one-line `<!-- … -->` comment repeating the
bullet. Leave it in place or delete it, but write your answer below it.

**Two commits, in this order.** The plan commit comes first, and `/review` checks that it
does:

```bash
# 1. Before any file under dbt_practice/models/day10 exists — notes.md with ## Plan filled in.
git add days/day10/notes.md && git commit -m "Day 10 plan"
```

```bash
# 2. After you have seen both runs green — before /genprompt.
git add dbt_practice/models/day10 dbt_practice/tests/day10 days/day10/notes.md && git commit -m "Day 10 as submitted"
```

**Submit only a solution you have seen build.** That has been missed four times (Days 1, 7, 8
and 9). Paste the final `Done.` line of both runs into `## Run log` *before* commit 2. If there
is no green line to paste, do not make the commit. And if the error is in the environment
rather than in your models, raise it.

Plus, in `days/day10/notes.md`:

- `## Plan`: **graded, committed alone in commit 1, before any SQL.** Three parts:
  1. **Grain.** For each mart column: which relation it is read from, and the grain at which it
     is computed. Then, for each relation the mart reads, *how many of its rows can match one
     order?* This question has been asked on Days 6, 7, 8 and 9 and has never been answered.
  2. **Hand-compile.** Before writing any Jinja, write out by hand the SQL expressions that the
     loop should produce for `card_order_count`, `card_amount_usd`, `other_order_count` and
     `other_amount_usd` under run 1's var. Then evaluate each of the four by hand against the
     seed rows of **M1, 2026-09** and of **M3, 2026-10**, payment by payment, and check the
     result against Expected Output.
  3. **Run 2.** Which files change between run 1 and run 2, and which cells of which rows change
     value.
- `## Test count`: the number of assertions V1–V8 ask for, the `dbt ls` number, and what the
  difference was if they ever differed.
- `## Red proof`: for each of V5, V6, V8, the temporary change, the pasted `FAIL n` line, and
  confirmation it was reverted.
- `## Assumptions`: anything you had to decide.
- `## Run log`: the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from both builds, every captured
  table, the compiled SQL, and the `grep` output, **pasted, not summarized.**
- `## Debrief answers`: the four questions below, in written English.

## Debrief questions

1. **Trade-off.** The method list is a project var. The alternative is to read it from the data
   at run time, with `run_query` or `dbt_utils.get_column_values` over
   `stg_d10_payments.payment_method`. Why is the var the better choice for this mart, and in what
   situation would you reverse that? For each choice, describe what happens to the mart on the
   night a new method first appears in the data.
2. Run 2 changed the mart's column set, and the mart rebuilt cleanly because it is a table.
   Suppose instead it were an incremental model under the adapter's default `on_schema_change`.
   What would run 2 have done to the `bnpl_*` columns, and what would `other_amount_usd` hold
   for the October rows afterwards? Which `on_schema_change` setting would you choose, and what
   would it still not fix?
3. At what point in a dbt invocation are `var()` and `{% for %}` resolved, and what text
   reaches DuckDB? Use the compiled file you captured after run 2. Then explain why a list built
   with `run_query` needs an `{% if execute %}` guard and a var does not.
4. A BI team asks for the long form instead: one row per (`merchant_id`, `order_month`,
   `payment_method`) with `order_count` and `amount_usd`. What does each shape make easy and
   hard? When a method is added, which consumers of each shape break, and who notices first?
