-- Looker Studio dataset: monthly_kpi_mart
-- Grain: one row per month.
-- Purpose: exact monthly KPI comparison without summing daily distinct counts.

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.monthly_kpi_mart` AS
WITH base_events AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    user_pseudo_id,
    event_name,
    ecommerce.purchase_revenue AS purchase_revenue,
    CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
monthly AS (
  SELECT
    month,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchasers,
    COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) AS purchase_sessions,
    COUNTIF(event_name = 'purchase') AS orders,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0)) AS revenue
  FROM base_events
  GROUP BY month
)
SELECT
  month,
  sessions,
  users,
  purchasers,
  purchase_sessions,
  orders,
  revenue,
  SAFE_DIVIDE(purchase_sessions, sessions) AS session_cvr,
  SAFE_DIVIDE(purchasers, users) AS user_cvr,
  SAFE_DIVIDE(revenue, orders) AS aov,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM monthly
ORDER BY month;

