-- dbt_project.yml's day9 block already declares staging as view; restated here so the model is self-describing.
{{ config(materialized='view') }}

with source as (

    select
        CUSTOMER_ID,
        CUSTOMER_NAME,
        PLAN_CODE,
        UPDATED_AT,
        BATCH_ID
    from {{ ref('raw_d9_customer_dump') }}

),

renamed as (

    select
        cast(CUSTOMER_ID   as varchar)   as customer_id,
        cast(CUSTOMER_NAME as varchar)   as customer_name,
        cast(PLAN_CODE     as varchar)   as plan_code,
        cast(UPDATED_AT    as timestamp) as updated_at,
        cast(BATCH_ID      as integer)   as batch_id
    from source

)

select
    customer_id,
    customer_name,
    plan_code,
    updated_at
from renamed
where batch_id = {{ var('d9_batch', 1) }}
