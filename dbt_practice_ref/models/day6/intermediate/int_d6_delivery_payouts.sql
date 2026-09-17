-- No dbt_project.yml entry for day6/intermediate, so this inherits the
-- project default and materializes as a view.

-- Collapses the line feed to delivery grain BEFORE it ever meets the header
-- feed. This is the whole point of the model: the header amount must not be
-- multiplied by the number of adjustment lines the delivery happens to own.

with deliveries as (

    select *
    from {{ ref('stg_d6_deliveries') }}
    where status <> 'CANCELLED'   -- cancelled deliveries leave the pipeline here,
                                  -- and take their adjustment lines with them

),

adjustments_by_delivery as (

    select
        delivery_id,
        sum(adj_amount_usd) as adjustment_total_usd
    from {{ ref('stg_d6_delivery_adjustments') }}
    group by delivery_id

)

select
    d.delivery_id,
    d.courier_id,
    d.city_code,
    d.delivery_date,
    d.status,
    cast(d.payout_base_usd as decimal(10,2))              as payout_base_usd,
    cast(coalesce(a.adjustment_total_usd, 0) as decimal(10,2)) as adjustment_total_usd

from deliveries d
left join adjustments_by_delivery a
       on d.delivery_id = a.delivery_id
