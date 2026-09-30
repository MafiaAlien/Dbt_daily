{{ config(materialized='ephemeral') }}
with customers as 
(
    select 
        * 
    from 
        {{ ref('ex_customers') }}
),

sales as (
    select 
        *
    from 
        {{ ref('ex_sales') }}
),

-- at least 10 transaction
valid_customers AS (
SELECT 
    CustomerID AS customer_id 
FROM 
    sales 
GROUP BY CustomerID
HAVING count(DISTINCT TransactionID) >= 10
),

-- calculate metrics of engagement rate
engagement AS (
    SELECT 
        CustomerID,
        ROUND(COUNT(DISTINCT CASE WHEN TRIM(Class) = 'GWP' THEN TransactionID END)* 100.0 / COUNT(DISTINCT TransactionID) , 2) AS engaged_rate 
    FROM 
        sales
    GROUP BY CustomerID
)

SELECT 
    CustomerID
FROM 
    engagement
WHERE 
    engaged_rate >= 10 AND CustomerID IN (SELECT customer_id FROM valid_customers)