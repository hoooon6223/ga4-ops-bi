-- Build managed BigQuery mart tables for the GA4 Operations BI portfolio.
-- Destination dataset:
-- `bigquery-457902.ga4_ops_bi`

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.daily_kpi_mart` AS
WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
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
daily AS (
  SELECT
    event_dt,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS users,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS purchasers,
    COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) AS purchase_sessions,
    COUNTIF(event_name = 'purchase') AS orders,
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
  SAFE_DIVIDE(revenue, orders) AS aov,
  SAFE_DIVIDE(revenue, sessions) AS revenue_per_session
FROM daily;

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.daily_funnel_mart` AS
WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    user_pseudo_id,
    event_name,
    device.category AS device_category,
    COALESCE(traffic_source.medium, '(not set)') AS medium,
    COALESCE(traffic_source.source, '(not set)') AS source,
    CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
session_flags AS (
  SELECT
    event_dt,
    session_id,
    ANY_VALUE(device_category) AS device_category,
    ANY_VALUE(source) AS source,
    ANY_VALUE(medium) AS medium,
    MAX(IF(event_name = 'session_start', 1, 0)) AS has_session_start,
    MAX(IF(event_name = 'view_item', 1, 0)) AS has_view_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) AS has_add_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) AS has_begin_checkout,
    MAX(IF(event_name = 'purchase', 1, 0)) AS has_purchase
  FROM base_events
  WHERE session_id IS NOT NULL
  GROUP BY event_dt, session_id
),
aggregated AS (
  SELECT
    event_dt,
    device_category,
    source,
    medium,
    CASE
      WHEN medium = 'organic' THEN 'Organic Search'
      WHEN medium IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN medium IN ('email') THEN 'Email'
      WHEN medium IN ('referral') THEN 'Referral'
      WHEN medium IN ('affiliate') THEN 'Affiliate'
      WHEN source = '(direct)' OR medium = '(none)' THEN 'Direct'
      ELSE 'Other'
    END AS channel_group,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT IF(has_view_item = 1, session_id, NULL)) AS view_item_sessions,
    COUNT(DISTINCT IF(has_add_to_cart = 1, session_id, NULL)) AS add_to_cart_sessions,
    COUNT(DISTINCT IF(has_begin_checkout = 1, session_id, NULL)) AS checkout_sessions,
    COUNT(DISTINCT IF(has_purchase = 1, session_id, NULL)) AS purchase_sessions
  FROM session_flags
  GROUP BY event_dt, device_category, source, medium, channel_group
)
SELECT
  event_dt AS date,
  device_category,
  source,
  medium,
  CONCAT(source, ' / ', medium) AS source_medium,
  channel_group,
  sessions,
  view_item_sessions,
  add_to_cart_sessions,
  checkout_sessions,
  purchase_sessions,
  SAFE_DIVIDE(view_item_sessions, sessions) AS session_to_view_rate,
  SAFE_DIVIDE(add_to_cart_sessions, view_item_sessions) AS view_to_cart_rate,
  SAFE_DIVIDE(checkout_sessions, add_to_cart_sessions) AS cart_to_checkout_rate,
  SAFE_DIVIDE(purchase_sessions, checkout_sessions) AS checkout_to_purchase_rate,
  SAFE_DIVIDE(purchase_sessions, sessions) AS session_to_purchase_rate
FROM aggregated;

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
FROM monthly;

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.current_month_kpi_mart` AS
WITH monthly AS (
  SELECT *
  FROM `bigquery-457902.ga4_ops_bi.monthly_kpi_mart`
),
current_period AS (
  SELECT *
  FROM monthly
  WHERE month = DATE '2021-01-01'
),
previous_period AS (
  SELECT *
  FROM monthly
  WHERE month = DATE '2020-12-01'
)
SELECT
  c.month AS current_month,
  p.month AS comparison_month,
  c.revenue,
  SAFE_DIVIDE(c.revenue - p.revenue, p.revenue) AS revenue_mom_pct,
  c.sessions,
  SAFE_DIVIDE(c.sessions - p.sessions, p.sessions) AS sessions_mom_pct,
  c.session_cvr,
  c.session_cvr - p.session_cvr AS session_cvr_mom_point,
  c.aov,
  SAFE_DIVIDE(c.aov - p.aov, p.aov) AS aov_mom_pct,
  c.revenue_per_session,
  SAFE_DIVIDE(c.revenue_per_session - p.revenue_per_session, p.revenue_per_session) AS revenue_per_session_mom_pct,
  c.orders,
  SAFE_DIVIDE(c.orders - p.orders, p.orders) AS orders_mom_pct
FROM current_period c
CROSS JOIN previous_period p;

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.daily_segment_mart` AS
WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    user_pseudo_id,
    event_name,
    device.category AS device_category,
    COALESCE(traffic_source.medium, '(not set)') AS medium,
    COALESCE(traffic_source.source, '(not set)') AS source,
    ecommerce.purchase_revenue AS purchase_revenue,
    CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),
user_first_visit AS (
  SELECT
    user_pseudo_id,
    MIN(event_dt) AS first_seen_date
  FROM base_events
  GROUP BY user_pseudo_id
),
aggregated AS (
  SELECT
    b.event_dt,
    b.device_category,
    b.source,
    b.medium,
    CASE
      WHEN b.medium = 'organic' THEN 'Organic Search'
      WHEN b.medium IN ('cpc', 'ppc', 'paidsearch') THEN 'Paid Search'
      WHEN b.medium IN ('email') THEN 'Email'
      WHEN b.medium IN ('referral') THEN 'Referral'
      WHEN b.medium IN ('affiliate') THEN 'Affiliate'
      WHEN b.source = '(direct)' OR b.medium = '(none)' THEN 'Direct'
      ELSE 'Other'
    END AS channel_group,
    IF(b.event_dt = u.first_seen_date, 'New', 'Returning') AS user_type,
    COUNT(DISTINCT b.session_id) AS sessions,
    COUNT(DISTINCT b.user_pseudo_id) AS users,
    COUNT(DISTINCT IF(b.event_name = 'purchase', b.user_pseudo_id, NULL)) AS purchasers,
    COUNT(DISTINCT IF(b.event_name = 'purchase', b.session_id, NULL)) AS purchase_sessions,
    COUNTIF(b.event_name = 'purchase') AS orders,
    SUM(IF(b.event_name = 'purchase', b.purchase_revenue, 0)) AS revenue
  FROM base_events b
  LEFT JOIN user_first_visit u
    ON b.user_pseudo_id = u.user_pseudo_id
  GROUP BY event_dt, device_category, source, medium, channel_group, user_type
)
SELECT
  event_dt AS date,
  device_category,
  source,
  medium,
  CONCAT(source, ' / ', medium) AS source_medium,
  channel_group,
  user_type,
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
FROM aggregated;
