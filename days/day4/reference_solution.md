Below is the complete Day 4 deliverable: three staging views, one mart table, two `schema.yml` files, and five singular tests.

`dbt_practice/models/day4/staging/stg_d4_sellers.sql`

```sql
{{ config(materialized='view') }}

-- Rename and cast only. No filtering, dedup, repair or imputation.
select
    cast(SELLER_ID   as varchar) as seller_id,
    cast(SELLER_NAME as varchar) as seller_name,
    cast(COUNTRY     as varchar) as country,
    cast(IS_ACTIVE   as boolean) as is_active
from {{ ref('raw_d4_sellers') }}
```

`dbt_practice/models/day4/staging/stg_d4_payouts.sql`

```sql
{{ config(materialized='view') }}

-- Rename and cast only. No filtering, dedup, repair or imputation.
select
    cast(PAYOUT_ID     as varchar)       as payout_id,
    cast(SELLER_ID     as varchar)       as seller_id,
    cast(PAYOUT_DATE   as date)          as payout_date,
    cast(STATUS        as varchar)       as status,
    cast(CURRENCY      as varchar)       as currency,
    cast(PAYOUT_AMOUNT as decimal(12,2)) as payout_amount
from {{ ref('raw_d4_payouts') }}
```

`dbt_practice/models/day4/staging/stg_d4_payout_lines.sql`

```sql
{{ config(materialized='view') }}

-- Rename and cast only. NULLs from the faulty May export pass through untouched:
-- L010 (orphan payout_id), L011 (null payout_id), L012 (null currency) all reach this view.
select
    cast(LINE_ID        as varchar)       as line_id,
    cast(PAYOUT_ID      as varchar)       as payout_id,
    cast(ORDER_REF      as varchar)       as order_ref,
    cast(CURRENCY       as varchar)       as currency,
    cast(LINE_AMOUNT    as decimal(12,2)) as line_amount,
    cast(PAYMENT_METHOD as varchar)       as payment_method
from {{ ref('raw_d4_payout_lines') }}
```

`dbt_practice/models/day4/marts/fct_d4_seller_payouts.sql`

```sql
{{ config(materialized='table') }}

with payouts as (

    select * from {{ ref('stg_d4_payouts') }}

),

sellers as (

    select * from {{ ref('stg_d4_sellers') }}

),

-- Lines are collapsed to payout grain BEFORE the header join, so the header-grain
-- counts (payout_count, paid_payout_count, paid_amount) cannot be fanned out by lines.
-- No filter here: the null-payout_id line and the P9999 line simply form groups that
-- match no header, so they contribute to nothing without being dropped.
lines_per_payout as (

    select
        payout_id,
        count(*) as line_count
    from {{ ref('stg_d4_payout_lines') }}
    group by 1

),

payouts_with_lines as (

    select
        p.seller_id,
        p.payout_id,
        p.status,
        p.payout_amount,
        coalesce(l.line_count, 0) as line_count
    from payouts p
    left join lines_per_payout l
        on p.payout_id = l.payout_id

),

seller_agg as (

    select
        seller_id,
        count(*)                                     as payout_count,
        count(case when status = 'PAID' then 1 end)  as paid_payout_count,
        cast(
            coalesce(sum(case when status = 'PAID' then payout_amount end), 0)
            as decimal(12,2)
        )                                            as paid_amount,
        cast(sum(line_count) as bigint)              as line_count
    from payouts_with_lines
    group by 1

)

-- Grain is driven by payouts, not by the seller master, so the join to sellers is a
-- left join used purely for the label.
select
    a.seller_id,
    s.seller_name,
    a.payout_count,
    a.paid_payout_count,
    a.paid_amount,
    a.line_count
from seller_agg a
left join sellers s
    on a.seller_id = s.seller_id
```

`dbt_practice/models/day4/staging/schema.yml`

```yaml
version: 2

models:

  - name: stg_d4_sellers
    description: >
      Seller master, one row per seller_id. Rename-and-cast passthrough of
      raw_d4_sellers. Enforces contract clauses C1-C3; C4 (is_active) is
      deliberately untested because the contract makes no guarantee about it.
    columns:

      - name: seller_id
        description: "Primary key. Unique and always present (C1)."
        data_tests:
          - unique
          - not_null

      - name: seller_name
        description: "Display name of the seller. Always present (C2)."
        data_tests:
          - not_null

      - name: country
        description: >
          ISO-style market code. Always present and restricted to the four
          markets the marketplace operates in (C3).
        data_tests:
          - not_null
          - accepted_values:
              values: ['US', 'DE', 'GB', 'PE']

      - name: is_active
        description: >
          Descriptive activity flag. The contract makes no guarantee about this
          column, so it carries no tests by design (C4).

  - name: stg_d4_payouts
    description: >
      Payout header feed, one row per payout_id. Rename-and-cast passthrough of
      raw_d4_payouts. Enforces C5-C9.
    columns:

      - name: payout_id
        description: "Primary key. Unique and always present (C5)."
        data_tests:
          - unique
          - not_null

      - name: seller_id
        description: >
          Owning seller. Always present, and must exist in the seller master
          (C6). Split into two assertions so a failure names either a missing
          value or a broken reference, not both.
        data_tests:
          - not_null
          - relationships:
              to: ref('stg_d4_sellers')
              field: seller_id

      - name: payout_date
        description: "Date the payout was issued. Not covered by the contract."

      - name: status
        description: "Lifecycle status. Always present, one of PAID / PENDING / FAILED (C7)."
        data_tests:
          - not_null
          - accepted_values:
              values: ['PAID', 'PENDING', 'FAILED']

      - name: currency
        description: "Settlement currency of the header. Always present, one of USD / EUR / GBP (C8)."
        data_tests:
          - not_null
          - accepted_values:
              values: ['USD', 'EUR', 'GBP']

      - name: payout_amount
        description: >
          Gross payout value. Always present (C9, presence half). The
          non-negativity half of C9 has no built-in generic test and lives in
          tests/day4/assert_d4_payout_amount_non_negative.sql.
        data_tests:
          - not_null

  - name: stg_d4_payout_lines
    description: >
      Payout line feed, one row per line_id. Rename-and-cast passthrough of
      raw_d4_payout_lines, including the three rows damaged by the faulty May
      export. Enforces C10-C14; the three known defects are surfaced at warn
      severity so they are reported on every run without blocking the build.
    columns:

      - name: line_id
        description: "Primary key. Unique and always present (C10)."
        data_tests:
          - unique
          - not_null

      - name: payout_id
        description: >
          Owning payout header. C11 requires every line to be attributable to an
          existing payout. Two separate defects exist upstream and each gets its
          own assertion: not_null catches lines that arrived with no payout_id
          (L011); relationships catches lines pointing at a header that does not
          exist (L010 -> P9999). Both are warn: they are the payments team's
          export bug, not a reason to stop the payout report.
        data_tests:
          - not_null:
              config:
                severity: warn
          - relationships:
              to: ref('stg_d4_payouts')
              field: payout_id
              config:
                severity: warn

      - name: order_ref
        description: "Marketplace order reference. Not covered by the contract."

      - name: currency
        description: >
          Settlement currency of the line (C12). The value-domain half is an
          error: any unexpected currency code is a real problem. The presence
          half is warn, because the same faulty export produced one line with no
          currency (L012), which must be reported but not imputed or blocked on.
        data_tests:
          - not_null:
              config:
                severity: warn
          - accepted_values:
              values: ['USD', 'EUR', 'GBP']

      - name: line_amount
        description: >
          Line value. Always present (C14, presence half); non-negativity is
          asserted in tests/day4/assert_d4_line_amount_non_negative.sql.
        data_tests:
          - not_null

      - name: payment_method
        description: >
          Settlement rail. C13 constrains the value only when one is recorded;
          a missing method means the marketplace default rail and is expected
          behaviour, so this column carries accepted_values but deliberately no
          not_null. accepted_values ignores NULLs, which is exactly the
          semantics C13 asks for.
        data_tests:
          - accepted_values:
              values: ['bank_transfer', 'paypal', 'wise']
```

`dbt_practice/models/day4/marts/schema.yml`

```yaml
version: 2

models:

  - name: fct_d4_seller_payouts
    description: >
      One row per seller_id appearing in stg_d4_payouts, with header-grain payout
      metrics and a line-grain line count rolled up through the payout header.
      Sellers with no payouts at all do not appear. Enforces C17-C19.
    columns:

      - name: seller_id
        description: "Grain of the table. Unique and never null (C17)."
        data_tests:
          - unique
          - not_null

      - name: seller_name
        description: >
          Seller display name carried from stg_d4_sellers. The contract states no
          rule for this column in the mart, so it is untested here; its presence
          is already guaranteed upstream by C2.

      - name: payout_count
        description: "Count of this seller's payouts in any status. Never null (C18)."
        data_tests:
          - not_null

      - name: paid_payout_count
        description: "Count of this seller's PAID payouts, zero if none. Never null (C18)."
        data_tests:
          - not_null

      - name: paid_amount
        description: >
          Sum of payout_amount over this seller's PAID payouts, zeroed rather
          than nulled when there are none. Never null (C18); non-negativity is
          asserted in tests/day4/assert_d4_paid_amount_non_negative.sql (C19).
        data_tests:
          - not_null

      - name: line_count
        description: >
          Count of payout lines belonging to this seller's payouts, in any
          status, zero if none. Lines that no payout claims are excluded by the
          join. Never null (C18).
        data_tests:
          - not_null
```

`dbt_practice/tests/day4/assert_d4_payout_amount_non_negative.sql`

```sql
-- C9 (value half): payout_amount is never negative.
select
    payout_id,
    payout_amount
from {{ ref('stg_d4_payouts') }}
where payout_amount < 0
```

`dbt_practice/tests/day4/assert_d4_line_amount_non_negative.sql`

```sql
-- C14 (value half): line_amount is never negative.
select
    line_id,
    payout_id,
    line_amount
from {{ ref('stg_d4_payout_lines') }}
where line_amount < 0
```

`dbt_practice/tests/day4/assert_d4_paid_amount_non_negative.sql`

```sql
-- C19: paid_amount in the mart is never negative.
select
    seller_id,
    paid_amount
from {{ ref('fct_d4_seller_payouts') }}
where paid_amount < 0
```

`dbt_practice/tests/day4/assert_d4_paid_payout_has_lines.sql`

```sql
-- C15: every payout whose status is PAID has at least one payout line.
-- Payouts in any other status may legitimately have none, so they are not checked.
select
    p.payout_id,
    p.seller_id,
    p.status
from {{ ref('stg_d4_payouts') }} p
left join {{ ref('stg_d4_payout_lines') }} l
    on p.payout_id = l.payout_id
where p.status = 'PAID'
group by p.payout_id, p.seller_id, p.status
having count(l.line_id) = 0
```

`dbt_practice/tests/day4/assert_d4_payout_amount_equals_line_sum.sql`

```sql
-- C16: for every payout that has at least one line, payout_amount equals the sum
-- of line_amount over that payout's lines. Payouts with no lines are out of scope,
-- which the inner join expresses. Lines whose payout_id is null or unmatched
-- (L011, L010) never join to a header, so they are neither dropped nor counted here.
with line_totals as (

    select
        payout_id,
        sum(line_amount) as line_total
    from {{ ref('stg_d4_payout_lines') }}
    group by 1

)

select
    p.payout_id,
    p.payout_amount,
    lt.line_total
from {{ ref('stg_d4_payouts') }} p
inner join line_totals lt
    on p.payout_id = lt.payout_id
where p.payout_amount <> lt.line_total
```

## Design notes

- **The three warnings come from three different assertions, by construction.** C11 is split into `not_null` (catches L011, the line with no `payout_id`) and `relationships` (catches L010, pointing at the non-existent P9999); C12's presence half is a third `not_null` (catches L012). dbt's built-in `relationships` test already filters NULL child keys, so it reports exactly one row rather than doubling up with the `not_null` — that separation is why each defect names one broken thing.
- **`accepted_values` ignores NULLs, and C13 depends on that.** `payment_method` gets `accepted_values` but deliberately no `not_null`, because a missing method means the default rail. The same property lets line `currency` keep `accepted_values` at error severity while its `not_null` sits at warn: the NULL row escapes the domain test and is reported once, by the assertion that actually means "missing".
- **Severity is set per test, not per column.** Only the three clauses the contract explicitly says must not block the build are downgraded to warn; everything else stays at the default error, including the mart tests, so a genuine modelling regression still fails.
- **Line counts are aggregated to payout grain before the header join.** Joining lines directly to headers and counting would fan out `payout_count` and inflate `paid_amount`; pre-aggregating keeps the header-grain measures honest. No `where payout_id is not null` filter is used anywhere — unmatched groups simply fail to join, which satisfies "contributes to nothing" without dropping a row.
- **No intermediate model was built.** The only reusable shape is lines-per-payout, which is consumed once, by one mart; promoting it to `int_d4_*` would add a DAG node and a materialization for a single four-line CTE. `data_tests:` is the dbt ≥1.8 spelling — on an older core, rename these keys to `tests:`.