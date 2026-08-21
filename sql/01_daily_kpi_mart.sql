-- BI dataset: daily_kpi_mart
-- Grain: one row per date.

DECLARE start_date STRING DEFAULT '20201101';
DECLARE end_date STRING DEFAULT '20210131';

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    user_pseudo_id,
    event_name,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
),
daily AS (
  SELECT
    event_dt,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchasers,
    COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) AS purchase_sessions,
    COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) AS orders,
    SUM(IF(event_name = 'purchase', purchase_revenue, 0)) AS revenue
  FROM base_events
  GROUP BY event_dt
)
SELECT
  event_dt AS date,
  sessions,
  users,
  purchasers,
  purchase_sessions,
  orders,
  revenue,
  SAFE_DIVIDE(purchase_sessions, sessions) AS session_cvr,
  SAFE_DIVIDE(purchasers, users) AS user_cvr,
  SAFE_DIVIDE(revenue, purchase_sessions) AS aov,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM daily
ORDER BY date;
