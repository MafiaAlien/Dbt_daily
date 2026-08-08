-- Grain: one row per order_id — the row from the latest ERP export of that order.

with source as (

    select * from {{ source('erp', 'orders') }}

),

renamed as (

    select
        cast(ORDER_ID       as integer)       as order_id,
        cast(CUSTOMER_CODE  as varchar)       as customer_id,
        cast(COUNTRY_CODE   as varchar)       as country_code,
        lower(trim(cast(ORDER_STATUS as varchar))) as order_status,
        cast(ORDER_TS       as timestamp)     as ordered_at,
        cast(AMOUNT_USD     as decimal(12,2)) as amount_usd,
        cast(EXPORTED_AT    as timestamp)     as exported_at

    from source

),

ranked as (

    select
        renamed.*,
        row_number() over (
            partition by order_id
            order by exported_at desc
        ) as export_rank

    from renamed

)

select
    order_id,
    customer_id,
    country_code,
    order_status,
    ordered_at,
    amount_usd,
    exported_at

from ranked
where export_rank = 1
