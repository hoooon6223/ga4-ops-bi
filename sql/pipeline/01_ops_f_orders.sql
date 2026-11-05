-- Step 1. Dedupe purchase events of @run_date into orders.
-- Rule: docs/ops_bi/02_ops_metric_definitions.md §1-1
--   order_key = 'T:' + transaction_id, or 'S:' + session_id + '|' + revenue when transaction_id is missing.
--   Keep the first event per order_key. Skip keys already loaded on earlier days (cross-day re-sends).
-- Idempotent: the @run_date partition is deleted and rebuilt.

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_f_orders` (
  order_date DATE,
  order_key STRING,
  transaction_id STRING,
  session_id STRING,
  user_pseudo_id STRING,
  order_ts INT64,
  purchase_revenue FLOAT64,
  item_revenue FLOAT64,
  has_revenue BOOL,
  has_tid BOOL,
  purchase_events INT64,
  device_category STRING,
  country STRING,
  medium STRING,
  loaded_at TIMESTAMP
)
PARTITION BY order_date;

DELETE FROM `bigquery-457902.ga4_ops_bi.ops_f_orders` WHERE order_date = @run_date;

INSERT INTO `bigquery-457902.ga4_ops_bi.ops_f_orders`
WITH p AS (
  SELECT
    event_timestamp,
    user_pseudo_id,
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS session_id,
    NULLIF(ecommerce.transaction_id, '(not set)') AS transaction_id,
    ecommerce.purchase_revenue AS purchase_revenue,
    (SELECT SUM(i.item_revenue) FROM UNNEST(items) AS i) AS item_revenue,
    device.category AS device_category,
    geo.country AS country,
    traffic_source.medium AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', @run_date)
    AND event_name = 'purchase'
),
keyed AS (
  SELECT
    *,
    COALESCE(
      CONCAT('T:', transaction_id),
      CONCAT('S:', session_id, '|', IFNULL(CAST(purchase_revenue AS STRING), 'null'))
    ) AS order_key
  FROM p
),
first_event AS (
  SELECT
    *,
    COUNT(*) OVER (PARTITION BY order_key) AS purchase_events
  FROM keyed
  WHERE TRUE
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_key ORDER BY event_timestamp) = 1
)
SELECT
  @run_date AS order_date,
  order_key,
  transaction_id,
  session_id,
  user_pseudo_id,
  event_timestamp AS order_ts,
  purchase_revenue,
  item_revenue,
  purchase_revenue IS NOT NULL AS has_revenue,
  transaction_id IS NOT NULL AS has_tid,
  purchase_events,
  device_category,
  country,
  medium,
  CURRENT_TIMESTAMP() AS loaded_at
FROM first_event
WHERE order_key NOT IN (
  SELECT order_key
  FROM `bigquery-457902.ga4_ops_bi.ops_f_orders`
  WHERE order_date < @run_date
);
