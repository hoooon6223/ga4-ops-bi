-- Step 2. Session-day table for @run_date: funnel reach flags + deduped orders rolled up by session.
-- Grain: session_date x session_id. A session crossing midnight counts once on each day (GA4 export is split by event_date).
-- Idempotent: the @run_date partition is deleted and rebuilt.

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_f_sessions` (
  session_date DATE,
  session_id STRING,
  user_pseudo_id STRING,
  is_new_user BOOL,
  has_view_item BOOL,
  has_add_to_cart BOOL,
  has_begin_checkout BOOL,
  has_purchase_event BOOL,
  orders INT64,
  orders_with_revenue INT64,
  revenue FLOAT64,
  device_category STRING,
  country STRING,
  medium STRING,
  loaded_at TIMESTAMP
)
PARTITION BY session_date;

-- Delete + insert are one transaction: a failure leaves the day's previous rows untouched.
BEGIN TRANSACTION;

DELETE FROM `bigquery-457902.ga4_ops_bi.ops_f_sessions` WHERE session_date = @run_date;

INSERT INTO `bigquery-457902.ga4_ops_bi.ops_f_sessions`
WITH e AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS session_id,
    device.category AS device_category,
    geo.country AS country,
    traffic_source.medium AS medium
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', @run_date)
),
s AS (
  SELECT
    session_id,
    ANY_VALUE(user_pseudo_id) AS user_pseudo_id,
    LOGICAL_OR(event_name = 'first_visit') AS is_new_user,
    LOGICAL_OR(event_name = 'view_item') AS has_view_item,
    LOGICAL_OR(event_name = 'add_to_cart') AS has_add_to_cart,
    LOGICAL_OR(event_name = 'begin_checkout') AS has_begin_checkout,
    LOGICAL_OR(event_name = 'purchase') AS has_purchase_event,
    ARRAY_AGG(STRUCT(device_category, country, medium) ORDER BY event_timestamp LIMIT 1)[OFFSET(0)] AS dims
  FROM e
  GROUP BY session_id
),
o AS (
  SELECT
    session_id,
    COUNT(*) AS orders,
    COUNTIF(has_revenue) AS orders_with_revenue,
    SUM(IFNULL(purchase_revenue, 0)) AS revenue
  FROM `bigquery-457902.ga4_ops_bi.ops_f_orders`
  WHERE order_date = @run_date
  GROUP BY session_id
)
SELECT
  @run_date AS session_date,
  s.session_id,
  s.user_pseudo_id,
  s.is_new_user,
  s.has_view_item,
  s.has_add_to_cart,
  s.has_begin_checkout,
  s.has_purchase_event,
  IFNULL(o.orders, 0) AS orders,
  IFNULL(o.orders_with_revenue, 0) AS orders_with_revenue,
  IFNULL(o.revenue, 0) AS revenue,
  s.dims.device_category,
  s.dims.country,
  s.dims.medium,
  CURRENT_TIMESTAMP() AS loaded_at
FROM s
LEFT JOIN o USING (session_id);

COMMIT TRANSACTION;
