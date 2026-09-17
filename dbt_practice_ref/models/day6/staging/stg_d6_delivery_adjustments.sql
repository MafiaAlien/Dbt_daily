{{ config(materialized='view') }}

-- Line feed: 0..n rows per delivery. An adjustment always arrives in the
-- same batch as its delivery, so the same batch filter keeps the two aligned.

select
    cast(adjustment_id   as varchar)       as adjustment_id,
    cast(delivery_id     as varchar)       as delivery_id,
    cast(adj_type        as varchar)       as adj_type,
    cast(adj_amount_usd  as decimal(10,2)) as adj_amount_usd

from {{ ref('raw_d6_delivery_adjustments') }}

where batch_id <= {{ var('d6_batch', 1) }}
