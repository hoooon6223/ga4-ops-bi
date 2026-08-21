-- Tableau dataset: daily_funnel_mart
-- Grain: one row per date, device, channel.
-- Funnel is session-based: a session is counted in a step if the event occurred at least once.

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
    CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    ) AS session_id
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN start_date AND end_date
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
FROM aggregated
ORDER BY date, device_category, channel_group, source_medium;

