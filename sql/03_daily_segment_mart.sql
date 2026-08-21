-- Tableau dataset: daily_segment_mart
-- Grain: one row per date, device, channel, source/medium, user type.

DECLARE start_date STRING DEFAULT '20201101';
DECLARE end_date STRING DEFAULT '20210131';

WITH base_events AS (
  SELECT
    PARSE_DATE('%Y%m%d', event_date) AS event_dt,
    user_pseudo_id,
    event_name,
    device.category AS device_category,
    COALESCE(traffic_source.medium, '(not set)') AS medium,
    COALESCE(traffic_source.source, '(not set)') AS source,
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
FROM aggregated
ORDER BY date, device_category, channel_group, source_medium, user_type;
