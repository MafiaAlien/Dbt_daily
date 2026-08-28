-- No config block: inherits the project default (view). One row per surviving
-- shipment. This is the model that collapses the two grains into one, so the
-- mart can be a plain group by with no fan-out.

with shipment_states as (

    select * from {{ ref('stg_d5_shipments') }}

),

ranked_states as (

    -- Portability note: DuckDB supports QUALIFY, but row_number() + a filtering
    -- CTE is used instead so this runs unchanged on Postgres et al.
    select
        shipment_id,
        warehouse_code,
        ship_date,
        status,
        shipping_cost_usd,
        row_number() over (
            partition by shipment_id
            order by updated_at desc
        ) as state_rank
    from shipment_states

),

latest_state as (

    select
        shipment_id,
        warehouse_code,
        ship_date,
        status,
        shipping_cost_usd
    from ranked_states
    where state_rank = 1

),

active_shipments as (

    -- A shipment whose LATEST status is CANCELLED contributes nothing anywhere,
    -- including its item lines, which are dropped by the join below.
    select *
    from latest_state
    where status <> 'CANCELLED'

),

item_totals as (

    select
        shipment_id,
        sum(quantity)       as item_quantity,
        sum(line_weight_kg) as total_weight_kg
    from {{ ref('stg_d5_shipment_items') }}
    group by shipment_id

)

select
    s.shipment_id,
    s.warehouse_code,
    s.ship_date,
    s.status,
    s.shipping_cost_usd,
    cast(coalesce(i.item_quantity, 0)   as integer)       as item_quantity,
    cast(coalesce(i.total_weight_kg, 0) as decimal(12,3)) as total_weight_kg
from active_shipments as s
left join item_totals as i
    on s.shipment_id = i.shipment_id
