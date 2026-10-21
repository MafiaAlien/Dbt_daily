{#- Payment SLA: a payment is loaded no more than this many calendar days after its invoice_date. -#}
{%- set payment_sla_days = 4 -%}

-- Overrides the day9/marts `table` default from dbt_project.yml (that block stays untouched).
{{
    config(
        materialized='incremental',
        unique_key=['invoice_date', 'plan_code'],
        incremental_strategy='delete+insert',
        on_schema_change='fail'
    )
}}

with invoice_revenue as (

    select
        invoice_date,
        plan_code,
        billed_usd,
        collected_usd
    from {{ ref('int_d9_invoice_revenue') }}

    {% if is_incremental() %}
    -- Reopen every invoice_date that tonight's load can still touch:
    -- invoice_date >= (latest invoice_date already in the mart) - SLA days. Derivation: notes.md, Plan part 4.
    -- Empty-but-existing target -> max() is null -> fall back to "everything".
    where invoice_date >= (
        select coalesce(
            cast({{ dbt.dateadd('day', -payment_sla_days, 'max(invoice_date)') }} as date),
            cast('1900-01-01' as date)
        )
        from {{ this }}
    )
    {% endif %}

),

daily_plan as (

    select
        invoice_date,
        plan_code,
        cast(count(*) as integer)                 as invoice_count,
        cast(sum(billed_usd) as decimal(12,2))    as billed_usd,
        cast(sum(collected_usd) as decimal(12,2)) as collected_usd
    from invoice_revenue
    group by invoice_date, plan_code

)

select
    invoice_date,
    plan_code,
    invoice_count,
    billed_usd,
    collected_usd,
    cast(billed_usd - collected_usd as decimal(12,2)) as outstanding_usd
from daily_plan
