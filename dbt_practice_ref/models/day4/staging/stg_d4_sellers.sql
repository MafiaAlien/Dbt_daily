{{ config(materialized='view') }}

-- Rename and cast only. No filtering, dedup, repair or imputation.
select
    cast(SELLER_ID   as varchar) as seller_id,
    cast(SELLER_NAME as varchar) as seller_name,
    cast(COUNTRY     as varchar) as country,
    cast(IS_ACTIVE   as boolean) as is_active
from {{ ref('raw_d4_sellers') }}
