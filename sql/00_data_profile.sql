-- Purpose:
-- Profile the GA4 public ecommerce sample before deciding final dashboard comparisons.
-- Dataset period: 2020-11-01 to 2021-01-31.
--
-- Source table:
-- `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

DECLARE start_date STRING DEFAULT '20201101';
DECLARE end_date STRING DEFAULT '20210131';

-- 1. Basic coverage
SELECT
  MIN(PARSE_DATE('%Y%m%d', event_date)) AS min_event_date,
  MAX(PARSE_DATE('%Y%m%d', event_date)) AS max_event_date,
  COUNT(DISTINCT event_date) AS day_count,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date;

-- 2. Event mix
SELECT
  event_name,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
GROUP BY event_name
ORDER BY event_count DESC;

-- 3. Monthly KPI sanity check
WITH events AS (
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
)
SELECT
  DATE_TRUNC(event_dt, MONTH) AS month,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchasers,
  COUNTIF(event_name = 'purchase') AS orders,
  SUM(IF(event_name = 'purchase', purchase_revenue, 0)) AS revenue,
  SAFE_DIVIDE(
    COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)),
    COUNT(DISTINCT session_id)
  ) AS session_cvr,
  SAFE_DIVIDE(
    SUM(IF(event_name = 'purchase', purchase_revenue, 0)),
    COUNTIF(event_name = 'purchase')
  ) AS aov
FROM events
GROUP BY month
ORDER BY month;

-- 4. Daily completeness check
SELECT
  PARSE_DATE('%Y%m%d', event_date) AS event_dt,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
GROUP BY event_dt
ORDER BY event_dt;
