{{ config(materialized='ephemeral') }}

with src as (
    select 
        *
    from 
        {{ ref('stg_d5_shipments') }}
   
)

select 
    *
from 
    src 
where 
    status <> 'CANCELLED'