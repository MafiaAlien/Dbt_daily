with src as (
    select 
        *
    from 
        {{ ref('raw_d4_sellers') }}
),

renamed as (
    select 
        CAST(SELLER_ID AS varchar ) as seller_id,
        CAST(SELLER_NAME AS varchar ) as seller_name,
        CAST(COUNTRY AS varchar ) as country,
        CAST(IS_ACTIVE AS boolean ) as is_active
    from 
        src 
)

select * from renamed 

