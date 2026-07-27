# dbt Daily Practice — Day 1

**Topic:** staging layer + `ref()` layering + schema tests
**Difficulty:** Easy
**Prerequisite course:** dbt Fundamentals

## Problem

A subscription-box company wants a per-customer order summary for its CRM team.

Build three models across two layers.

### Layer 1 — staging (materialized as **view**)

Staging models are a 1:1 pass over their seed: rename columns to `snake_case`, cast to
the stated type, and nothing else. **Staging must not filter, deduplicate, or aggregate
— every seed row appears in its staging model.**

`stg_d1_customers` — from seed `raw_d1_customers`

| column | type | source column | note |
|---|---|---|---|
| `customer_id` | integer | `CustomerID` | |
| `customer_name` | varchar | `FullName` | |
| `email` | varchar | `Email` | lower-cased |
| `signup_date` | date | `SignupDate` | |
| `country` | varchar | `Country` | |

`stg_d1_orders` — from seed `raw_d1_orders`

| column | type | source column | note |
|---|---|---|---|
| `order_id` | integer | `OrderID` | |
| `customer_id` | integer | `CustomerID` | |
| `ordered_at` | timestamp | `OrderTs` | |
| `amount` | `decimal(10,2)` | `Amount` | cast explicitly; do not leave it floating-point |
| `status` | varchar | `Status` | |

### Layer 2 — mart (materialized as **table**)

`fct_d1_customer_orders` — **grain: one row per customer in `stg_d1_customers`.**

Every customer in `stg_d1_customers` appears in this model exactly once, whether or not
they have ordered anything.

| column | definition |
|---|---|
| `customer_id` | from `stg_d1_customers` |
| `customer_name` | from `stg_d1_customers` |
| `order_count` | **count of orders attributed to this customer, in any `status`.** A customer with no orders has `order_count = 0`. |
| `total_amount` | **sum of `amount` over those same orders.** An order whose `amount` is missing contributes `0`. A customer whose orders all have a missing `amount`, and a customer with no orders at all, both have `total_amount = 0.00`. Never null. |

An order is "attributed to" a customer when its `customer_id` matches. Orders that
carry no `customer_id` are guest checkouts: they belong to no customer and therefore
contribute to no row of this mart.

### Layering rules

- The mart reads from staging via `ref()`. It must not read a seed directly.
- Materializations are already configured for you in `dbt_project.yml` under the `day1:`
  block — do not add per-model `config()` blocks to override them.

## Input

Both files go under `dbt_practice/seeds/day1/`.

`raw_d1_customers.csv`

```csv
CustomerID,FullName,Email,SignupDate,Country
1,Alice Chen,alice@example.com,2024-01-05,US
2,Bob Ortiz,BOB@Example.com,2024-01-11,US
3,Carol Ng,carol@example.com,2024-02-02,CA
4,Dan Wu,dan@example.com,2024-02-20,US
```

`raw_d1_orders.csv`

```csv
OrderID,CustomerID,OrderTs,Amount,Status
1001,1,2024-03-01 10:00:00,49.90,completed
1002,1,2024-03-05 14:30:00,25.10,completed
1003,2,2024-03-02 09:15:00,80.00,completed
1004,2,2024-03-09 11:45:00,,pending
1005,3,2024-03-07 16:20:00,,pending
1006,,2024-03-08 12:00:00,15.00,completed
1007,,2024-03-10 08:30:00,22.50,completed
```

An empty field is a missing value, not a zero and not an empty string.

## Expected Output

`fct_d1_customer_orders` — comparison is **order-insensitive**; sorted by `customer_id`
here only for readability.

| customer_id | customer_name | order_count | total_amount |
|---|---|---|---|
| 1 | Alice Chen | 2 | 75.00 |
| 2 | Bob Ortiz | 2 | 80.00 |
| 3 | Carol Ng | 1 | 0.00 |
| 4 | Dan Wu | 0 | 0.00 |

Exactly 4 rows.

## Verification

Use these two `schema.yml` files **verbatim**. They are the acceptance criteria: do not
weaken, remove, or add tests in order to make a run go green.

`dbt_practice/models/day1/staging/schema.yml`

```yaml
version: 2

models:
  - name: stg_d1_customers
    description: "One row per customer, renamed and recast from raw_d1_customers."
    columns:
      - name: customer_id
        description: "Natural key of the customer."
        data_tests:
          - unique
          - not_null
      - name: email
        description: "Lower-cased contact email."
        data_tests:
          - not_null

  - name: stg_d1_orders
    description: "One row per order, renamed and recast from raw_d1_orders."
    columns:
      - name: order_id
        description: "Natural key of the order."
        data_tests:
          - unique
          - not_null
      - name: customer_id
        description: "Customer who placed the order, if any."
        data_tests:
          - relationships:
              to: ref('stg_d1_customers')
              field: customer_id
```

`dbt_practice/models/day1/marts/schema.yml`

```yaml
version: 2

models:
  - name: fct_d1_customer_orders
    description: "One row per customer, with lifetime order count and captured amount."
    columns:
      - name: customer_id
        description: "Grain of this model."
        data_tests:
          - unique
          - not_null
          - relationships:
              to: ref('stg_d1_customers')
              field: customer_id
      - name: order_count
        description: "Orders placed by this customer, any status. Zero if none."
        data_tests:
          - not_null
      - name: total_amount
        description: "Sum of captured order amounts. Zero if none captured."
        data_tests:
          - not_null
```

Pass condition: `dbt build --select path:models/day1` is green **and**
`fct_d1_customer_orders` matches Expected Output exactly.

Suggested loop while working:

```
docker compose exec dbt dbt build --select path:models/day1
```

## Deliverables

```
dbt_practice/seeds/day1/raw_d1_customers.csv
dbt_practice/seeds/day1/raw_d1_orders.csv
dbt_practice/models/day1/staging/stg_d1_customers.sql
dbt_practice/models/day1/staging/stg_d1_orders.sql
dbt_practice/models/day1/staging/schema.yml
dbt_practice/models/day1/marts/fct_d1_customer_orders.sql
dbt_practice/models/day1/marts/schema.yml
```

Plus written English answers to the Debrief questions in `days/day1/notes.md`, and any
assumption you had to make recorded under `## Assumptions` in the same file.

## Debrief questions

Answer in written English after Stage 4 (Verify). Draft them while solving.

1. **Trade-off.** This problem fixes staging as `view` and the mart as `table`. Name the
   specific condition under which you would reverse each choice, and say what signal
   would tell you the reversal is needed. Be concrete about cost — what gets more
   expensive, and for whom.

2. dbt ships `relationships` as a built-in generic test. State precisely what it asserts
   and what it does **not** assert. Read the compiled SQL under `target/compiled/` for
   the `relationships` test on `stg_d1_orders.customer_id` and quote the clause that
   settles the question.

3. **Trade-off.** This problem forbids filtering in the staging layer. Give the argument
   for that convention, then name a concrete situation where you would break it and
   explain how you would keep the exception from spreading.
