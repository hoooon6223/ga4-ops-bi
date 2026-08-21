-- Data quality checks for GA4 Operations BI mart design.
-- Run these before trusting dashboard numbers.

DECLARE start_date STRING DEFAULT '20201101';
DECLARE end_date STRING DEFAULT '20210131';

CREATE TEMP TABLE base_events AS
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    event_timestamp,
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
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date;

-- 1. Missing core identifiers
SELECT
  COUNT(*) AS events,
  COUNTIF(user_pseudo_id IS NULL) AS null_user_pseudo_id_events,
  COUNTIF(session_id IS NULL) AS null_session_id_events
FROM base_events;

-- 2. Purchase transaction quality
SELECT
  COUNTIF(event_name = 'purchase') AS purchase_events,
  COUNTIF(event_name = 'purchase' AND transaction_id IS NULL) AS purchase_events_without_transaction_id,
  COUNT(DISTINCT IF(event_name = 'purchase', transaction_id, NULL)) AS distinct_transaction_ids,
  SUM(IF(event_name = 'purchase', purchase_revenue, 0)) AS purchase_revenue
FROM base_events;

-- 3. Duplicate transaction IDs
SELECT
  transaction_id,
  COUNT(*) AS purchase_event_count,
  SUM(purchase_revenue) AS revenue_sum
FROM base_events
WHERE event_name = 'purchase'
  AND transaction_id IS NOT NULL
GROUP BY transaction_id
HAVING purchase_event_count > 1
ORDER BY purchase_event_count DESC, revenue_sum DESC;

-- 4. Revenue reconciliation by month
SELECT
  DATE_TRUNC(event_dt, MONTH) AS month,
  COUNTIF(event_name = 'purchase') AS purchase_events,
  COUNT(DISTINCT IF(event_name = 'purchase', transaction_id, NULL)) AS distinct_transaction_ids,
  SUM(IF(event_name = 'purchase', purchase_revenue, 0)) AS revenue_from_events
FROM base_events
GROUP BY month
ORDER BY month;

-- 5. Session grain check
SELECT
  DATE_TRUNC(event_dt, MONTH) AS month,
  COUNT(DISTINCT session_id) AS sessions,
  COUNT(*) AS events,
  SAFE_DIVIDE(COUNT(*), COUNT(DISTINCT session_id)) AS events_per_session
FROM base_events
GROUP BY month
ORDER BY month;
