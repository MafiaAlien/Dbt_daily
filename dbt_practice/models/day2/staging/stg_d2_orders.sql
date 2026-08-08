WITH 
src AS (
    SELECT 
        *
    FROM 
        {{ source('erp', 'orders') }}
),

renamed AS (
    SELECT 
        CAST(order_id AS INTEGER) AS order_id,
        CAST(customer_code AS VARCHAR) AS customer_id,
        CAST(country_code AS VARCHAR) AS country_code,
        CAST(lower(trim(order_status)) AS VARCHAR) AS order_status,
        CAST(order_ts AS TIMESTAMP) AS ordered_at,
        CAST(amount_usd AS DECIMAL(12, 2)) AS amount_usd,
        CAST(exported_at AS TIMESTAMP) AS exported_at,
        ROW_NUMBER()OVER(partition by order_id order by exported_at DESC) as rn
    FROM
        src
),

most_recent_updated AS (
    SELECT 
        *
    FROM 
        renamed
    WHERE rn = 1
)


SELECT * FROM  most_recent_updated


