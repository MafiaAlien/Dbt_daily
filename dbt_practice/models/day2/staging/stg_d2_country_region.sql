with 
src as (
    select 
        * 
    from 
        {{ ref('raw_d2_country_region') }}
),

renamed as (
    select 
        cast(country_code as varchar) as country_code,
        cast(region as varchar) as region 
    from 
        src 
)

select * from renamed