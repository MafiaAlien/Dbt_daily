# dbt Daily Practice — Day 4

**Topic:** test design — `accepted_values` / `relationships` / singular tests, and
translating a written data contract into a dbt test suite
**Difficulty:** Medium
**Prerequisite course:** dbt Fundamentals (+ Advanced Testing)

## Problem

A marketplace pays its sellers. The payments team publishes three feeds — a seller
master, a payout header feed, and a payout line feed — and has written a **data
contract** describing what those feeds guarantee.

The modelling this day is deliberately thin: three staging views that rename and cast,
and one mart. **The deliverable that is actually being graded is the test suite.**

Days 1–3 handed you the `schema.yml` files verbatim. This one does not. The `##
Verification` section below gives you the contract in prose and the pass condition; you
decide, clause by clause, which test enforces it, which model and column it hangs on,
and at what severity.

### Two constraints

- **No packages this day.** `dbt_utils`, `dbt_expectations`, `audit_helper` and the rest
  are installed in this project, and are **out of bounds for Day 4**. Anything the four
  built-in generic tests cannot express, you write as a singular test in
  `dbt_practice/tests/day4/`. Writing those by hand is the point; `dbt_utils` is Day 10.
- **Staging is rename-and-cast only.** No filtering, no deduplication, no repair, no
  imputation. If a feed carries a bad row, that row reaches `stg_d4_*` intact. The
  contract below tells you what to do about it, and dropping it is never the answer.

### Layer 1 — staging

Each model is 1:1 with its seed.

`stg_d4_sellers` — from seed `raw_d4_sellers`. **Grain: one row per `seller_id`.** 4 rows.

| column | type | source column |
|---|---|---|
| `seller_id` | varchar | `SELLER_ID` |
| `seller_name` | varchar | `SELLER_NAME` |
| `country` | varchar | `COUNTRY` |
| `is_active` | boolean | `IS_ACTIVE` |

`stg_d4_payouts` — from seed `raw_d4_payouts`. **Grain: one row per `payout_id`.** 7 rows.

| column | type | source column |
|---|---|---|
| `payout_id` | varchar | `PAYOUT_ID` |
| `seller_id` | varchar | `SELLER_ID` |
| `payout_date` | date | `PAYOUT_DATE` |
| `status` | varchar | `STATUS` |
| `currency` | varchar | `CURRENCY` |
| `payout_amount` | `decimal(12,2)` | `PAYOUT_AMOUNT` |

`stg_d4_payout_lines` — from seed `raw_d4_payout_lines`.
**Grain: one row per `line_id`.** 12 rows.

| column | type | source column |
|---|---|---|
| `line_id` | varchar | `LINE_ID` |
| `payout_id` | varchar | `PAYOUT_ID` |
| `order_ref` | varchar | `ORDER_REF` |
| `currency` | varchar | `CURRENCY` |
| `line_amount` | `decimal(12,2)` | `LINE_AMOUNT` |
| `payment_method` | varchar | `PAYMENT_METHOD` |

Some columns in this feed carry NULLs. Pass every one of them through unchanged.

### Layer 2 — intermediate (optional)

`dbt_practice/models/day4/intermediate/` exists and is yours to use or leave empty. It
has no `dbt_project.yml` entry, so anything you put there materializes as a view under
the project default. Nothing this day requires an intermediate model; if you build one,
name it `int_d4_*` and say in `notes.md` why it earned its place.

### Layer 3 — mart

#### `fct_d4_seller_payouts` — a table

**Grain: one row per `seller_id` that appears in `stg_d4_payouts`.** 4 rows.

| column | definition |
|---|---|
| `seller_id` | grain. Never null. |
| `seller_name` | from `stg_d4_sellers`. |
| `payout_count` | count of payouts for this seller, **in any status**. |
| `paid_payout_count` | count of those whose `status` is `'PAID'`. Zero if none. |
| `paid_amount` | sum of `payout_amount` over this seller's `'PAID'` payouts only. Zero if the seller has none. Type `decimal(12,2)`. **Never null.** |
| `line_count` | count of payout lines belonging to this seller's payouts, in any status. Zero if none. |

`payout_count` and `line_count` are counts of two different things at two different
grains, and they live in the same row. Decide where each one is aggregated before you
write the join.

A line that no payout claims belongs to no seller and contributes to nothing here.

## Input

All three files are already written to `dbt_practice/seeds/day4/` and loaded — you do not
create them. They are shown here so the data is readable next to the requirements.

`raw_d4_sellers.csv`

```csv
SELLER_ID,SELLER_NAME,COUNTRY,IS_ACTIVE
SL01,Northwind Crafts,US,true
SL02,Baltic Timber,DE,true
SL03,Thames Bindery,GB,false
SL04,Andes Textiles,PE,true
```

`raw_d4_payouts.csv`

```csv
PAYOUT_ID,SELLER_ID,PAYOUT_DATE,STATUS,CURRENCY,PAYOUT_AMOUNT
P1001,SL01,2026-05-04,PAID,USD,1350.00
P1002,SL01,2026-05-18,PAID,USD,890.50
P1003,SL02,2026-05-04,PAID,EUR,2100.00
P1004,SL02,2026-05-20,PENDING,EUR,750.00
P1005,SL03,2026-05-11,PAID,GBP,640.00
P1006,SL03,2026-05-25,FAILED,GBP,410.00
P1007,SL04,2026-05-19,PENDING,USD,300.00
```

`raw_d4_payout_lines.csv`

```csv
LINE_ID,PAYOUT_ID,ORDER_REF,CURRENCY,LINE_AMOUNT,PAYMENT_METHOD
L001,P1001,ORD-8801,USD,500.00,bank_transfer
L002,P1001,ORD-8815,USD,450.00,paypal
L003,P1001,ORD-8822,USD,400.00,
L004,P1002,ORD-8904,USD,600.50,bank_transfer
L005,P1002,ORD-8917,USD,290.00,wise
L006,P1003,ORD-9002,EUR,1200.00,bank_transfer
L007,P1003,ORD-9014,EUR,750.00,
L008,P1005,ORD-9101,GBP,640.00,paypal
L009,P1006,ORD-9120,GBP,410.00,bank_transfer
L010,P9999,ORD-9203,USD,275.00,wise
L011,,ORD-9211,EUR,180.00,paypal
L012,P1003,ORD-9018,,150.00,bank_transfer
```

An empty field is a missing value — not a zero, not an empty string.

## Expected Output

Comparison is **order-insensitive**; sorted by `seller_id` here only for readability.

`fct_d4_seller_payouts` — exactly 4 rows.

| seller_id | seller_name | payout_count | paid_payout_count | paid_amount | line_count |
|---|---|---|---|---|---|
| SL01 | Northwind Crafts | 2 | 2 | 2240.50 | 5 |
| SL02 | Baltic Timber | 2 | 1 | 2100.00 | 3 |
| SL03 | Thames Bindery | 2 | 1 | 640.00 | 2 |
| SL04 | Andes Textiles | 1 | 0 | 0.00 | 0 |

**Row counts and every cell are part of the answer.** A suite can be green and this table
can still be wrong. Compare the table, not the test summary.

## Verification

### The data contract

This is the document the payments team publishes. It is prose on purpose: turning it
into a test suite is the exercise. Every clause below is either enforced by a test you
write, or it is not enforced at all.

**How to read it.** Use the narrowest built-in generic test that expresses a rule. Where
one clause needs two assertions to be fully covered, write two — a failing test should
name one broken thing, not "something in this column". Where no built-in test can
express a rule, write a singular test in `dbt_practice/tests/day4/`.

**Seller master** — enforced on `stg_d4_sellers`

- **C1.** `seller_id` identifies a seller uniquely and is always present.
- **C2.** `seller_name` is always present.
- **C3.** `country` is always present and is one of `US`, `DE`, `GB`, `PE` — the four
  markets the marketplace operates in.
- **C4.** `is_active` is descriptive. The contract makes no guarantee about it and it is
  not to be tested.

**Payout headers** — enforced on `stg_d4_payouts`

- **C5.** `payout_id` identifies a payout uniquely and is always present.
- **C6.** `seller_id` is always present, and every payout belongs to a seller that exists
  in the seller master.
- **C7.** `status` is always present and is exactly one of `PAID`, `PENDING`, `FAILED`.
- **C8.** `currency` is always present and is one of `USD`, `EUR`, `GBP`.
- **C9.** `payout_amount` is always present and is never negative.

**Payout lines** — enforced on `stg_d4_payout_lines`

- **C10.** `line_id` identifies a line uniquely and is always present.
- **C11.** Every line is attributable to a payout that exists in the payout header feed.
  **The May export job was faulty.** Some lines arrived with no `payout_id` at all;
  others carry a `payout_id` the header feed does not contain. Both are upstream defects
  owned by the payments team, and both must be surfaced **on every run**. They must
  **not** fail the build — this pipeline is not allowed to block a payout report over
  someone else's export bug — and the offending rows must **not** be dropped, filtered,
  or repaired anywhere in this project.
- **C12.** `currency` on a line is always present and is one of `USD`, `EUR`, `GBP`. The
  same faulty export also produced a line with no currency at all. Same handling as C11:
  surface it, do not fail the build, do not impute a value for it.
- **C13.** `payment_method`, **when it is present**, is one of `bank_transfer`, `paypal`,
  `wise`. A line settled on the marketplace's default rail records no method. **That
  absence is expected behaviour and is not a defect** — the contract makes no
  presence guarantee for this column.
- **C14.** `line_amount` is always present and is never negative.

**Cross-model rules**

- **C15.** Every payout whose `status` is `PAID` has at least one payout line. A payout
  in any other status may legitimately have none yet.
- **C16.** For every payout that has at least one line, `payout_amount` equals the sum of
  `line_amount` over that payout's lines.

**Mart** — enforced on `fct_d4_seller_payouts`

- **C17.** `seller_id` identifies a row uniquely and is always present.
- **C18.** `payout_count`, `paid_payout_count`, `paid_amount` and `line_count` are always
  present.
- **C19.** `paid_amount` is never negative.

### Where the tests live

```
dbt_practice/models/day4/staging/schema.yml
dbt_practice/models/day4/marts/schema.yml
dbt_practice/tests/day4/*.sql
```

Give every model and every tested column a `description`. A test suite nobody can read
is not a contract.

Singular tests are picked up by `--select path:models/day4` automatically when their SQL
`ref()`s a day-4 model. If you write one that does not — see
`dbt_practice/tests/day3/assert_d3_materializations.sql` for the `-- depends_on:` comment
form that puts it in the DAG anyway.

### Pass condition

```
docker compose exec dbt dbt build --select path:models/day4
```

must finish with

```
Done. PASS=<n> WARN=3 ERROR=0 SKIP=0 ...
```

**and** `fct_d4_seller_payouts` must match Expected Output exactly.

Three things about that line:

- **`ERROR=0`.** No test in your suite fails.
- **`WARN=3`.** The contract requires three separate defects to be surfaced without
  failing the build. Each of the three comes from a **different** assertion; no single
  test is expected to catch more than one of them. If you see `WARN=0`, `WARN=1` or
  `WARN=2`, your suite is silent about something the contract says must be reported —
  and being silent is the failure mode this day is about.
- **`PASS=<n>` is deliberately not given.** How many tests the contract needs is part of
  what you are working out.

You may not reach `WARN=3` by editing seeds, by filtering rows in a model, or by
weakening a clause. The three defective rows are input, and they stay.

## Deliverables

```
dbt_practice/models/day4/staging/stg_d4_sellers.sql
dbt_practice/models/day4/staging/stg_d4_payouts.sql
dbt_practice/models/day4/staging/stg_d4_payout_lines.sql
dbt_practice/models/day4/staging/schema.yml
dbt_practice/models/day4/marts/fct_d4_seller_payouts.sql
dbt_practice/models/day4/marts/schema.yml
dbt_practice/tests/day4/          (one .sql per clause no generic test can express — you decide which, and you name them)
```

Plus, in `days/day4/notes.md`:

- `## Assumptions` — anything the contract left you to decide.
- `## Contract coverage` — **a graded deliverable, not a formality.** One row per clause
  C1–C19:

  | Clause | Test | Where it lives | Severity |
  |---|---|---|---|
  | C1 | `unique`, `not_null` | `models/day4/staging/schema.yml` → `stg_d4_sellers.seller_id` | error |

  A clause with no test gets a row saying so and why. This table is what an analytics
  engineer hands a reviewer, and in the interview it is the artifact that proves you read
  the contract rather than guessed at it.
- `## Debrief answers` — the four questions below, in written English.

`notes.md` has been left blank or near-blank on Days 1, 2 and 3. It is a deliverable like
any other, and this day it carries the coverage table.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **What generic tests say about NULL.** `stg_d4_payout_lines.currency` contains a NULL
   and the `accepted_values` test on that column passes anyway. Open the compiled test
   under `target/compiled/` and quote the line that explains why. Do the same for the
   `relationships` test on `payout_id` and quote the clause that makes it blind to the
   row with no `payout_id`. Then state the general rule about what a built-in generic
   test asserts in the presence of NULL, and name which of the four built-ins is the
   exception.

2. **Trade-off — severity.** C11 and C12 are reported without failing the build. Give the
   argument for `warn` over `error` here, then name the condition under which you would
   flip them to `error`, and what has to be true of the payments team's own process for
   that flip to be safe rather than merely strict. Then name the config that keeps
   severity at `warn` until the defect count crosses a threshold, and the config that
   persists the failing rows somewhere a human can chase them tomorrow.

3. **Tests that are too broad.** C15 and C16 are both qualified — neither applies to every
   payout. For each, write down the exact rows your test must **not** return, and the
   clause in your SQL that excludes them. Then: a test that is too broad and a test that
   is too narrow are both wrong. Which of the two do you find out about faster, and what
   does that asymmetry imply about which mistake is more dangerous in a nightly run?

4. **Trade-off — where the assertion lives.** C16 is enforced here as a singular test
   after the fact. Name two other places the same rule could live — one further upstream,
   one further downstream — and say what each buys and what each gives up. Then say which
   you would choose if the line feed were 40 million rows a day, and what you would
   measure to justify the choice.
