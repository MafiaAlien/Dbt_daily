## dbt_project.yml (materialization config — no per-model `config()` blocks)

```yaml
models:
  dbt_practice:
    day1:
      staging:
        +materialized: view
      marts:
        +materialized: table
```

---

## Staging

`dbt_practice/models/day1/staging/stg_d1_customers.sql`

```sql
with source as (

    select * from {{ ref('raw_d1_customers') }}

),

renamed as (

    select
        cast(CustomerID as integer)   as customer_id,
        cast(FullName as varchar)     as customer_name,
        lower(cast(Email as varchar)) as email,
        cast(SignupDate as date)      as signup_date,
        cast(Country as varchar)      as country

    from source

)

select * from renamed
```

`dbt_practice/models/day1/staging/stg_d1_orders.sql`

```sql
with source as (

    select * from {{ ref('raw_d1_orders') }}

),

renamed as (

    select
        cast(OrderID as integer)          as order_id,
        cast(CustomerID as integer)       as customer_id,
        cast(OrderTs as timestamp)        as ordered_at,
        cast(Amount as decimal(10, 2))    as amount,
        cast(Status as varchar)           as status

    from source

)

select * from renamed
```

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
              arguments:
                to: ref('stg_d1_customers')
                field: customer_id
```

---

## Mart

`dbt_practice/models/day1/marts/fct_d1_customer_orders.sql`

```sql
with customers as (

    select * from {{ ref('stg_d1_customers') }}

),

orders as (

    select * from {{ ref('stg_d1_orders') }}

),

-- Aggregate first, at order grain, so the join below cannot fan out customers.
-- Guest checkouts (null customer_id) are dropped here: they belong to no customer.
order_agg as (

    select
        customer_id,
        count(*)                  as order_count,
        sum(coalesce(amount, 0))  as total_amount

    from orders
    where customer_id is not null
    group by customer_id

),

final as (

    select
        customers.customer_id,
        customers.customer_name,
        coalesce(order_agg.order_count, 0)                          as order_count,
        cast(coalesce(order_agg.total_amount, 0) as decimal(10, 2)) as total_amount

    from customers
    left join order_agg
        on customers.customer_id = order_agg.customer_id

)

select * from final
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
              arguments:
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

---

## Design notes

- **Two different nulls, two different `coalesce`s.** `coalesce(amount, 0)` *inside* `sum()` handles an order with a missing amount (Carol keeps `order_count = 1` but contributes `0.00`); the outer `coalesce(..., 0)` handles a customer with no matching aggregate row at all (Dan). Using `count(*)` rather than `count(amount)` is what keeps Bob at 2 orders despite his pending order having no amount.
- **Pre-aggregate, then left join.** Joining first and grouping afterwards would also work here, but aggregating at order grain keeps the customer grain structurally guaranteed rather than relying on the `group by` to restore it — which is what the `unique`/`not_null` tests on `customer_id` are checking.
- **Guest checkouts are excluded in the mart, not in staging.** Filtering them out of `stg_d1_orders` would violate the 1:1 staging rule. They pass the staging `relationships` test anyway, because dbt's built-in relationships test discards rows where the from-field is null before joining.
- **`decimal(10,2)` cast in staging, re-cast at the end.** Casting in staging means the sum is exact decimal arithmetic rather than binary float (`49.90 + 25.10` must land on exactly `75.00`); the final cast pins the scale back to `(10,2)`, since summing a decimal widens the result type.
- **No DuckDB-specific syntax.** Everything uses ANSI `cast(x as t)` and `lower()` rather than `x::t`, so the models port to Postgres/Snowflake/BigQuery unchanged apart from `decimal` spelling.