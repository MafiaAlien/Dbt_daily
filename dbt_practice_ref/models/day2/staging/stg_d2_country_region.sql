-- Grain: one row per country_code. 1:1 with the seed — no filtering.

with source as (

    select * from {{ ref('raw_d2_country_region') }}

)

select
    cast(country_code as varchar) as country_code,
    cast(region       as varchar) as region

from source
