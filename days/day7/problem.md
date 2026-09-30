# dbt Daily Practice — Day 7

**Topic:** snapshots — `dbt snapshot` with the timestamp strategy, what
`dbt_valid_from` / `dbt_valid_to` actually mean, and joining a fact to the version of a
dimension that was in effect at the time
**Difficulty:** Medium
**Prerequisite course:** Snapshots / SCD

## Problem

A B2B logistics SaaS bills its customers by contract tier. The tier changes — accounts
upgrade, downgrade, move billing region, and occasionally churn. The operational system
keeps **only the current state** of each account; it overwrites in place and keeps no
history. Finance needs to answer two different questions off the same account data:

- *What tier is this account on today?* — a current dimension.
- *What tier was this account on when it placed that order?* — an as-of-then attribution.

The second question is the one the source system cannot answer, and the one
`dbt snapshot` exists for. Everything in this day is in service of it.

The trap of the day is not hidden and you should still expect to hit it: the two
questions above look like the same join, and one of them is right.

### The feeds

- `raw_d7_account_versions` — the account feed. It is **append-only in the warehouse**:
  every time the operational system overwrites an account, the ingestion job lands a new
  row here with the new `UPDATED_AT`. Several versions of the same account can exist.
  `UPDATED_AT` is set by the operational system at the moment of the change and is
  trustworthy: it never moves backwards and two versions of the same account never share
  it.
- `raw_d7_orders` — orders. **Static: fully loaded from the start, not batched, one row
  per `ORDER_ID`, never restated.** It does not participate in the batch simulation below.

`ACCOUNT_STATUS` is `ACTIVE` or `CHURNED`. A churn is an ordinary version like any other —
it has an `UPDATED_AT` and it lands in the feed. **Accounts are never deleted from the
feed**, so there is no hard-delete case this day and `hard_deletes` is not part of the
exercise.

### Simulating three nightly snapshot runs

A snapshot only records what it can see at the moment it runs. That cadence *is* the
subject, so the day is three runs, not one. There is no scheduler here, so the batch
boundary is a var. The staging model over the account feed ends with exactly this clause —
copy it verbatim, it is not the exercise:

```sql
where batch_id <= {{ var('d7_batch', 1) }}
```

Run 1 leaves the var at its default. Run 2 passes `--vars '{d7_batch: 2}'`, run 3
`--vars '{d7_batch: 3}'`. Exact commands are in `## Verification`.

**All three runs are graded**, and the snapshot is graded after each. The two marts are
graded after run 3 only.

**The snapshot table is the one thing in this project that is not reproducible from
source.** Run the three runs out of order, or twice, and the history you built is wrong
and no rebuild recovers it. `## Verification` has a `### Starting over` block. Read it
before you start, not after.

### Layer 1 — staging (views)

`stg_d7_account_versions` — from seed `raw_d7_account_versions`.
**Grain: one row per (`account_id`, `updated_at`) — 3 rows at `d7_batch=1`, 6 at
`d7_batch=2`, 10 at `d7_batch=3`.** Rename and cast only; no filtering and no
deduplication beyond the `batch_id` clause above.

| column | type | source column |
|---|---|---|
| `account_id` | varchar | `ACCOUNT_ID` |
| `account_name` | varchar | `ACCOUNT_NAME` |
| `contract_tier` | varchar | `CONTRACT_TIER` |
| `billing_region` | varchar | `BILLING_REGION` |
| `account_status` | varchar | `ACCOUNT_STATUS` |
| `updated_at` | timestamp | `UPDATED_AT` |

`stg_d7_orders` — from seed `raw_d7_orders`.
**Grain: one row per `order_id` — 13 rows, at every batch.**

| column | type | source column |
|---|---|---|
| `order_id` | varchar | `ORDER_ID` |
| `account_id` | varchar | `ACCOUNT_ID` |
| `order_ts` | timestamp | `ORDER_TS` |
| `order_amount_usd` | `decimal(10,2)` | `ORDER_AMOUNT_USD` |

`batch_id` is used by the filter and is **not** published out of either staging model.
Both models expose exactly the columns listed above, in that order.

### Layer 2 — intermediate (view, required)

`int_d7_account_feed_latest` — from `stg_d7_account_versions`.

**Grain: one row per `account_id` — the version with the greatest `updated_at` among
those the current batch can see.** Same columns as `stg_d7_account_versions`, unchanged.

This model exists because of what a snapshot is. A snapshot compares *the current state
of a relation* against the history it has already stored; it does not ingest a version
feed. **Its relation must therefore yield exactly one row per `account_id`.** Feeding it
several rows for one key does not build history faster — it corrupts the history it does
build.

`dbt_practice/models/day7/intermediate/` has no `dbt_project.yml` entry, so it
materializes as a **view** under dbt's own default. That is fine; leave it.

Note, and keep it for debrief question 2: **the versions this model drops are gone for
good.** If two versions of one account land in the same batch, the snapshot never sees
the earlier one, and no later run can recover it. The data in `## Input` contains exactly
this case.

### Layer 3 — the snapshot

`snap_d7_accounts`, in `dbt_practice/snapshots/day7/`.

- Defined in **YAML**, with a `snapshots:` block — not the legacy `{% snapshot %}` SQL
  block. Say in `notes.md` what changed in dbt 1.9 and why you would not write the old
  form in a new project today.
- Its relation is `int_d7_account_feed_latest`, by `ref()`.
- Strategy, `unique_key` and `updated_at` are yours to set. `dbt_project.yml` configures
  nothing about this snapshot on purpose; its `day7:` block is not yours to edit.
- Leave `dbt_valid_to_current` at its default. The current version's `dbt_valid_to` is
  `NULL`, and the models below must cope with that rather than configure it away.

The snapshot publishes the four dbt-managed columns on top of the relation's own:
`dbt_scd_id`, `dbt_updated_at`, `dbt_valid_from`, `dbt_valid_to`. **`dbt_scd_id` and
`dbt_updated_at` are not to be selected into either mart.**

### Layer 4 — marts (tables)

#### `dim_d7_accounts_current`

**Grain: one row per account that is currently active.** An account whose current version
is `CHURNED` produces **no row** — not a row flagged inactive, no row.

| column | type | definition |
|---|---|---|
| `account_id` | varchar | grain |
| `account_name` | varchar | from the current version |
| `contract_tier` | varchar | from the current version |
| `billing_region` | varchar | from the current version |
| `current_since` | timestamp | the `dbt_valid_from` of the current version |

#### `fct_d7_orders_attributed`

**Grain: one row per `order_id` in `stg_d7_orders` — all 13, always.** An order is never
dropped for want of a matching account version, and the mart never publishes a `NULL` in
any column.

| column | type | definition |
|---|---|---|
| `order_id` | varchar | grain |
| `account_id` | varchar | from `stg_d7_orders` |
| `order_ts` | timestamp | from `stg_d7_orders` |
| `order_amount_usd` | `decimal(10,2)` | from `stg_d7_orders` |
| `tier_at_order` | varchar | `contract_tier` of the account version **in effect at `order_ts`**, else `UNKNOWN` |
| `region_at_order` | varchar | `billing_region` of that same version, else `UNKNOWN` |
| `current_tier` | varchar | `contract_tier` from `dim_d7_accounts_current`, else `UNKNOWN` |

**"In effect at `order_ts`"** means exactly one version of that account, and you decide
which one by writing the predicate down. Two things it has to survive, both present in
this data:

- An order whose `order_ts` falls **exactly on** a version boundary. One version ends at
  that instant and the next begins at it. Exactly one of them is in effect. Decide which,
  and make sure the predicate agrees with your decision on both sides.
- An order placed **before the account's first version**. `dbt_valid_from` on a first
  version is that version's `updated_at`, not the beginning of time. No version is in
  effect; the answer is `UNKNOWN`, and the order still appears.

`tier_at_order` and `current_tier` are different columns for a reason and disagree on
several rows. If they agree on every row, you built one of them wrong — see debrief
question 4.

## Input

`dbt_practice/seeds/day7/raw_d7_account_versions.csv` — already loaded, do not edit.

```csv
ACCOUNT_ID,ACCOUNT_NAME,CONTRACT_TIER,BILLING_REGION,ACCOUNT_STATUS,UPDATED_AT,BATCH_ID
A100,Northwind Logistics,STANDARD,EMEA,ACTIVE,2026-03-01 00:00:00,1
A200,Helios Freight,STANDARD,AMER,ACTIVE,2026-03-02 00:00:00,1
A300,Cobalt Retail,PREMIUM,AMER,ACTIVE,2026-03-03 00:00:00,1
A100,Northwind Logistics,PREMIUM,EMEA,ACTIVE,2026-03-12 09:30:00,2
A400,Vela Agritech,STANDARD,APAC,ACTIVE,2026-03-14 10:00:00,2
A300,Cobalt Retail,PREMIUM,AMER,CHURNED,2026-03-18 16:00:00,2
A200,Helios Freight,PREMIUM,AMER,ACTIVE,2026-03-15 08:00:00,3
A100,Northwind Logistics,PREMIUM,UK,ACTIVE,2026-03-20 14:00:00,3
A200,Helios Freight,ENTERPRISE,AMER,ACTIVE,2026-03-22 11:00:00,3
A400,Vela Agritech,PREMIUM,APAC,ACTIVE,2026-03-25 07:45:00,3
```

`dbt_practice/seeds/day7/raw_d7_orders.csv` — already loaded, do not edit.

```csv
ORDER_ID,ACCOUNT_ID,ORDER_TS,ORDER_AMOUNT_USD
O-001,A100,2026-03-05 10:00:00,1200.00
O-002,A100,2026-03-12 09:30:00,800.50
O-003,A100,2026-03-12 09:29:59,640.00
O-004,A100,2026-03-24 08:15:00,2100.00
O-005,A200,2026-03-04 12:00:00,450.25
O-006,A200,2026-03-18 09:00:00,1750.00
O-007,A200,2026-03-26 17:30:00,3300.00
O-008,A300,2026-03-05 09:00:00,980.00
O-009,A300,2026-03-19 11:00:00,120.00
O-010,A400,2026-03-10 14:20:00,275.00
O-011,A400,2026-03-14 10:00:00,510.75
O-012,A400,2026-03-27 06:00:00,1430.00
O-013,A200,2026-03-22 11:00:00,2250.00
```

## Expected Output

### `snap_d7_accounts` after each run

Ordered by `account_id`, then `dbt_valid_from`. Only these six columns are shown;
`dbt_scd_id` and `dbt_updated_at` exist and are not compared. **All three are graded.**

#### After run 1 — `d7_batch` at its default (3 rows)

| account_id | contract_tier | billing_region | account_status | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|---|
| A100 | STANDARD | EMEA | ACTIVE | 2026-03-01 00:00:00 | *(null)* |
| A200 | STANDARD | AMER | ACTIVE | 2026-03-02 00:00:00 | *(null)* |
| A300 | PREMIUM | AMER | ACTIVE | 2026-03-03 00:00:00 | *(null)* |

#### After run 2 — `--vars '{d7_batch: 2}'` (6 rows)

| account_id | contract_tier | billing_region | account_status | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|---|
| A100 | STANDARD | EMEA | ACTIVE | 2026-03-01 00:00:00 | 2026-03-12 09:30:00 |
| A100 | PREMIUM | EMEA | ACTIVE | 2026-03-12 09:30:00 | *(null)* |
| A200 | STANDARD | AMER | ACTIVE | 2026-03-02 00:00:00 | *(null)* |
| A300 | PREMIUM | AMER | ACTIVE | 2026-03-03 00:00:00 | 2026-03-18 16:00:00 |
| A300 | PREMIUM | AMER | CHURNED | 2026-03-18 16:00:00 | *(null)* |
| A400 | STANDARD | APAC | ACTIVE | 2026-03-14 10:00:00 | *(null)* |

#### After run 3 — `--vars '{d7_batch: 3}'` (9 rows)

| account_id | contract_tier | billing_region | account_status | dbt_valid_from | dbt_valid_to |
|---|---|---|---|---|---|
| A100 | STANDARD | EMEA | ACTIVE | 2026-03-01 00:00:00 | 2026-03-12 09:30:00 |
| A100 | PREMIUM | EMEA | ACTIVE | 2026-03-12 09:30:00 | 2026-03-20 14:00:00 |
| A100 | PREMIUM | UK | ACTIVE | 2026-03-20 14:00:00 | *(null)* |
| A200 | STANDARD | AMER | ACTIVE | 2026-03-02 00:00:00 | 2026-03-22 11:00:00 |
| A200 | ENTERPRISE | AMER | ACTIVE | 2026-03-22 11:00:00 | *(null)* |
| A300 | PREMIUM | AMER | ACTIVE | 2026-03-03 00:00:00 | 2026-03-18 16:00:00 |
| A300 | PREMIUM | AMER | CHURNED | 2026-03-18 16:00:00 | *(null)* |
| A400 | STANDARD | APAC | ACTIVE | 2026-03-14 10:00:00 | 2026-03-25 07:45:00 |
| A400 | PREMIUM | APAC | ACTIVE | 2026-03-25 07:45:00 | *(null)* |

**Nine rows for ten input versions.** One version in `## Input` is in no window of this
table, at any run. Find it before you write the marts — it is debrief question 2, and it
decides one cell of the fact.

### `dim_d7_accounts_current` after run 3 (3 rows)

Ordered by `account_id`.

| account_id | account_name | contract_tier | billing_region | current_since |
|---|---|---|---|---|
| A100 | Northwind Logistics | PREMIUM | UK | 2026-03-20 14:00:00 |
| A200 | Helios Freight | ENTERPRISE | AMER | 2026-03-22 11:00:00 |
| A400 | Vela Agritech | PREMIUM | APAC | 2026-03-25 07:45:00 |

### `fct_d7_orders_attributed` after run 3 (13 rows)

Ordered by `order_id`.

| order_id | account_id | order_ts | order_amount_usd | tier_at_order | region_at_order | current_tier |
|---|---|---|---|---|---|---|
| O-001 | A100 | 2026-03-05 10:00:00 | 1200.00 | STANDARD | EMEA | PREMIUM |
| O-002 | A100 | 2026-03-12 09:30:00 | 800.50 | PREMIUM | EMEA | PREMIUM |
| O-003 | A100 | 2026-03-12 09:29:59 | 640.00 | STANDARD | EMEA | PREMIUM |
| O-004 | A100 | 2026-03-24 08:15:00 | 2100.00 | PREMIUM | UK | PREMIUM |
| O-005 | A200 | 2026-03-04 12:00:00 | 450.25 | STANDARD | AMER | ENTERPRISE |
| O-006 | A200 | 2026-03-18 09:00:00 | 1750.00 | STANDARD | AMER | ENTERPRISE |
| O-007 | A200 | 2026-03-26 17:30:00 | 3300.00 | ENTERPRISE | AMER | ENTERPRISE |
| O-008 | A300 | 2026-03-05 09:00:00 | 980.00 | PREMIUM | AMER | UNKNOWN |
| O-009 | A300 | 2026-03-19 11:00:00 | 120.00 | PREMIUM | AMER | UNKNOWN |
| O-010 | A400 | 2026-03-10 14:20:00 | 275.00 | UNKNOWN | UNKNOWN | PREMIUM |
| O-011 | A400 | 2026-03-14 10:00:00 | 510.75 | STANDARD | APAC | PREMIUM |
| O-012 | A400 | 2026-03-27 06:00:00 | 1430.00 | PREMIUM | APAC | PREMIUM |
| O-013 | A200 | 2026-03-22 11:00:00 | 2250.00 | ENTERPRISE | AMER | ENTERPRISE |

`sum(order_amount_usd)` over the mart is **15806.50**, which is `sum` over
`stg_d7_orders`. If yours is higher, you are counting an order twice. If lower, you have
dropped one.

**Read the three columns on the right against each other before you write anything.**
Eight rows have `tier_at_order` different from `current_tier`. Three rows sit exactly on
a `dbt_valid_from`, two of them interior — one version ends at that instant and the next
begins at it. One row is `UNKNOWN` on the left and known on the right, and one account is
known on the left and `UNKNOWN` on the right. Each of those is a different mistake if you
get it wrong, and only one of them turns a test red.

## Verification

### Tests you must write

The generic tests are named; the singular ones are stated as intent and you translate
them.

**No packages.** `dbt_utils` and friends are installed; they are out of bounds this day.
Anything the four built-in generic tests cannot express is a **singular test** in
`dbt_practice/tests/day7/`, one file per assertion, named after what it asserts.

**V1 — `stg_d7_account_versions`, generic.** `not_null` on `account_id`, `account_name`,
`contract_tier`, `billing_region`, `account_status`, `updated_at`. `accepted_values` on
`contract_tier`: `STANDARD`, `PREMIUM`, `ENTERPRISE`. `accepted_values` on
`account_status`: `ACTIVE`, `CHURNED`.
No `unique` here — the grain is composite, and V3 covers it. Say in one sentence why a
`unique` on `account_id` would be wrong on this model and right on the next one.

**V2 — `stg_d7_orders`, generic.** `unique` and `not_null` on `order_id`. `not_null` on
`account_id`, `order_ts`, `order_amount_usd`.

**V3 — `int_d7_account_feed_latest`, generic.** `unique` and `not_null` on `account_id`.

**V4 — the snapshot, generic.** `not_null` on `account_id`, `contract_tier`,
`dbt_valid_from`. `accepted_values` on `contract_tier`: `STANDARD`, `PREMIUM`,
`ENTERPRISE`. These go in a YAML `snapshots:` block — a snapshot takes tests exactly the
way a model does, and this one is worth having because the snapshot is the artifact you
cannot rebuild.

**V5 — the snapshot, intent.** Every `account_id` in the snapshot has **exactly one** row
with `dbt_valid_to is null`. Not at most one — exactly one.

**V6 — the snapshot, intent.** No account has two versions whose validity windows
overlap, and no window is empty. Treat a window as `[dbt_valid_from, dbt_valid_to)`, with
a `NULL` `dbt_valid_to` meaning "open, extends forever". This is the assertion that
defines SCD2; write it so that it would catch an overlap, not only a duplicate.

**V7 — `dim_d7_accounts_current`, generic.** `unique` and `not_null` on `account_id`.
`not_null` on the other four columns.

**V8 — `fct_d7_orders_attributed`, generic.** `unique` and `not_null` on `order_id`.
`not_null` on all seven columns. `accepted_values` on `tier_at_order`: `STANDARD`,
`PREMIUM`, `ENTERPRISE`, `UNKNOWN`.

**V9 — fact, intent — the reconciliation.** In one singular test, both directions:

> Every `order_id` in `stg_d7_orders` appears in the mart exactly once, the mart
> contains no `order_id` that is not in `stg_d7_orders`, and each row's
> `order_amount_usd` equals the staging row's.

**Both directions, and read this before you write it.** A test shaped as
`stg left join mart ... where mart.col <> stg.col` cannot fire on a missing mart row,
because `x <> NULL` is `NULL`, not `TRUE`. That was Day 6's V7 and it was the one
direction Day 6 was built around. A row the mart never wrote is a live failure mode here
too — an inner join to the snapshot drops an order in this data.

**V10 — fact, intent.** A row has `tier_at_order = 'UNKNOWN'` **only if** no version of
that account in the snapshot has a window containing its `order_ts`. Equivalently: there
is no row of the mart that is `UNKNOWN` while a covering version exists. This is the test
that catches a predicate which is merely too narrow rather than outright wrong.

**V11 — fact, intent.** Every row's `current_tier` agrees with `dim_d7_accounts_current`
for that account, and is `UNKNOWN` exactly when the account has no row there.

V5, V6, V9, V10 and V11 must be part of `dbt build`, so they run on **every** run, not
just when you remember to invoke them.

### Count your tests before you trust them

Day 6 declared eight assertions on a model whose name it misspelled by one character.
dbt binds a YAML patch **by name**; an unmatched patch is a warning, not an error, so all
eight tests were silently dropped and the build still said `WARN=0 ERROR=0`. A test that
never registered and a test that passed look identical in the `Done. PASS=…` line.

So, before run 1: count the assertions V1–V11 ask for, write that number into
`notes.md`, then run

```bash
docker compose exec dbt dbt ls --resource-type test --select path:models/day7 path:snapshots/day7 path:tests/day7 --quiet
```

and compare the two numbers. If they differ, find out why before you go any further.

### Starting over

A snapshot accumulates. If you need to restart the three-run protocol — wrong order, a
run repeated, a bad `unique_key` on run 1 — **the snapshot table must be dropped first**,
or your history is built on top of the old history and nothing you do afterwards fixes
it. This is environment plumbing, not part of the exercise:

```bash
docker compose exec dbt python3 -c "import duckdb; duckdb.connect('/workspace/practice.duckdb').execute('drop table if exists main.snap_d7_accounts')"
```

Then start again at run 1. Nothing else in the project needs resetting.

### One warning that is not yours

Until your first model exists under `day7/staging/` and `day7/marts/`, every dbt command
prints:

```
[WARNING]: Configuration paths exist in your dbt_project.yml file which do not apply to
any resources. There are 2 unused configuration paths: models.dbt_practice.day7.staging,
models.dbt_practice.day7.marts
```

That is the `day7:` block waiting for its models. It disappears on its own and it does
not affect the `Done. … WARN=…` count. Do not spend time on it, and do not edit the
`day7:` block to silence it.

### The three runs

```bash
# Run 1 — first nightly load.
docker compose exec dbt dbt build --select path:models/day7 path:snapshots/day7
```

```bash
# capture the snapshot after run 1
docker compose exec dbt dbt show --inline "select account_id, contract_tier, billing_region, account_status, dbt_valid_from, dbt_valid_to from {{ ref('snap_d7_accounts') }} order by 1, 5" --limit 30
```

```bash
# Run 2 — second nightly load.
docker compose exec dbt dbt build --select path:models/day7 path:snapshots/day7 --vars '{d7_batch: 2}'
```

```bash
# capture the snapshot after run 2
docker compose exec dbt dbt show --inline "select account_id, contract_tier, billing_region, account_status, dbt_valid_from, dbt_valid_to from {{ ref('snap_d7_accounts') }} order by 1, 5" --limit 30
```

```bash
# Run 3 — third nightly load.
docker compose exec dbt dbt build --select path:models/day7 path:snapshots/day7 --vars '{d7_batch: 3}'
```

```bash
# capture the snapshot after run 3
docker compose exec dbt dbt show --inline "select account_id, contract_tier, billing_region, account_status, dbt_valid_from, dbt_valid_to from {{ ref('snap_d7_accounts') }} order by 1, 5" --limit 30
```

```bash
# capture dim_d7_accounts_current
docker compose exec dbt dbt show --inline "select * from {{ ref('dim_d7_accounts_current') }} order by 1" --limit 30
```

```bash
# capture fct_d7_orders_attributed
docker compose exec dbt dbt show --inline "select * from {{ ref('fct_d7_orders_attributed') }} order by 1" --limit 30
```

Do **not** pass `--full-refresh` anywhere in this day. What it would do to the snapshot
is debrief question 3; do not find out empirically on the run you are being graded on.

### Pass condition

All six of the following, or it is not a pass:

1. All three runs green — `ERROR=0`, `WARN=0`, `SKIP=0`, and the snapshot actually
   ran on each (`OK snapshotted`, not `SKIP`).
2. The test count from `dbt ls` equals the number of assertions V1–V11 ask for.
3. The snapshot matches the 3-row, 6-row and 9-row tables cell for cell, including the
   `NULL`s and the timestamps.
4. `dim_d7_accounts_current` matches its 3-row table cell for cell.
5. `fct_d7_orders_attributed` matches its 13-row table cell for cell, including column
   types.
6. `sum(order_amount_usd)` over the mart is exactly 15806.50.

Green tests are necessary and not sufficient. At least one trap this day passes all
eleven verification items and is only visible by comparing cells.

## Deliverables

```
dbt_practice/models/day7/staging/stg_d7_account_versions.sql
dbt_practice/models/day7/staging/stg_d7_orders.sql
dbt_practice/models/day7/staging/schema.yml
dbt_practice/models/day7/intermediate/int_d7_account_feed_latest.sql
dbt_practice/models/day7/intermediate/schema.yml
dbt_practice/snapshots/day7/snap_d7_accounts.yml
dbt_practice/models/day7/marts/dim_d7_accounts_current.sql
dbt_practice/models/day7/marts/fct_d7_orders_attributed.sql
dbt_practice/models/day7/marts/schema.yml
dbt_practice/tests/day7/          (one .sql per intent assertion — V5, V6, V9, V10, V11)
```

**Commit your models before `/review` runs.**

```bash
git add dbt_practice/models/day7 dbt_practice/snapshots/day7 dbt_practice/tests/day7 && git commit -m "Day 7 as submitted"
```

This instruction was in Day 6's `## Deliverables` in bold, with both prior occurrences
cited, and it was not run: `models/day6/staging/schema.yml` was rewritten at 14:24, after
the verdict commit, after the review's builds, and after the typo in it had been named as
the review's first Critical finding. That is three consecutive days — 4, 5, 6 — on which
the graded file was edited after results were visible and no pristine copy existed, so
the grade rested on a file dump. Same discipline as committing the verdict, applied to
the solution. **Until this runs, every grade in the log is provisional.**

Plus, in `days/day7/notes.md`:

- `## Interval plan` — **a graded deliverable, and the first thing you write, before any
  SQL.** Four lines:
  1. The predicate for "the version in effect at `order_ts`", written out in full,
     including the boundary operators on both ends and the `dbt_valid_to is null` case.
  2. For each of the three right-hand columns of the fact — `tier_at_order`,
     `region_at_order`, `current_tier` — which relation it comes from and by which join.
  3. How many rows of the snapshot can match a single row of `stg_d7_orders` under your
     predicate, and what makes that number 1 rather than 2.
  4. The two rows of `## Expected Output` that your predicate decides, named by
     `order_id`, and what each would become if you flipped one operator.

  Day 5's version of this table was filled in and still put a header-level amount at the
  wrong grain; Day 6's agreed with the SQL for the first time, but its follow-up prompt
  about how many rows can match was left blank. That prompt is line 3 here.

- `## Snapshot config decisions` — strategy, `unique_key`, `updated_at`, and where each
  is configured. Plus: why the YAML form and not the legacy `{% snapshot %}` block, and
  what `dbt_valid_from` is set to on a **first** version under the strategy you chose.

- `## Test count` — the number of assertions V1–V11 ask for, the number `dbt ls`
  reported, and, if they ever differed, what the difference was.

- `## Assumptions` — anything you had to decide.

- `## Run log` — the `Done. PASS=… WARN=… ERROR=… SKIP=…` line from all three builds,
  plus the five captured tables, pasted. Not summarized, pasted.

- `## Debrief answers` — the four questions below, in written English.

`notes.md` has now been left blank, near-blank, or stale on Days 1, 2, 3, 4, 5 and 6 —
six days, five of them consecutive. On Day 6 the blank section was `## Watermark plan`,
and the derivation it asked for *was* the `>` versus `>=` decision that ended up being
the day's one surviving spec violation. `## Interval plan` above is the same shape: it
asks for the boundary decision in words before the join is written. Treat it as code.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **The boundary and the open end.** Quote your point-in-time predicate. Then, using the
   actual rows in `## Expected Output`:
   (a) Name every mart cell that changes if you write
   `order_ts between dbt_valid_from and dbt_valid_to`, including what happens to the row
   count and to `sum(order_amount_usd)`, and say which of V1–V11 fire and which stay
   green.
   (b) Name every cell that changes if you write
   `order_ts between dbt_valid_from and coalesce(dbt_valid_to, '9999-12-31')` instead —
   this one fixes the open end and keeps the other bug — and say which tests fire.
   (c) Say why an inner join to the snapshot loses exactly one order here, name it, and
   say which test catches it and which do not.

2. **Trade-off — snapshot cadence versus source history.** One version in `## Input` is
   in no window of `snap_d7_accounts`. Name it, name the order whose `tier_at_order` is
   therefore arguably wrong, and say what the true answer would have been. Then: this
   feed is append-only and holds every version, so an SCD2 dimension could be built from
   it directly with `lead(updated_at) over (partition by account_id order by updated_at)`
   and no snapshot at all. Give the condition under which you would ship that instead of
   `dbt snapshot`, what it costs you, and the two things `dbt snapshot` gives you that the
   window-function version cannot — one of which is the reason the operational system's
   overwrite behaviour was mentioned at all.

3. **Trade-off — the strategy, and the thing you cannot rebuild.** Why `timestamp` rather
   than `check` here, and what specifically would break if `UPDATED_AT` were set by the
   ingestion job rather than by the source system. State what `check` costs in exchange
   and the condition under which you would pay it. Then: someone runs
   `dbt build --full-refresh` against production to fix an unrelated model. Say what that
   does to `snap_d7_accounts`, what config prevents it, and — since the snapshot is
   downstream of nothing but a view over a seed in *this* project but not in production —
   what your backup story for snapshot tables is.

4. **Where "as of then" lives.** Name the eight rows where `tier_at_order` and
   `current_tier` differ, and give one business question that each column is the right
   answer to. Then: a colleague proposes deleting `tier_at_order` and joining everything
   to `dim_d7_accounts_current`, on the grounds that it is one join instead of two and
   "the tier is the tier". Give the exact report whose historical numbers would silently
   change every time an account upgrades, say how much revenue moves between tiers in
   *this* data if you make that substitution, and name the test in your V1–V11 suite that
   would catch it — or, if none would, say so plainly and write the assertion that would.
