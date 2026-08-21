-- BI dataset: monthly_funnel_mart
-- Grain: one row per month.
-- Funnel type: cumulative loose session funnel.
-- Purpose: diagnose which conversion step drove the January 2021 CVR drop.
--
-- Notes:
-- GA4 sample data can contain checkout events without add_to_cart events.
-- To keep step conversion rates monotonic and interpretable, each stage after
-- Product View requires all prior stages to be present in the same session.
-- Total purchase sessions are kept separately as the KPI CVR denominator.

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.monthly_funnel_mart` AS
WITH base_events AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    user_pseudo_id,
    event_name,
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
    month,
    session_id,
    MAX(IF(event_name = 'view_item', 1, 0)) = 1 AS has_view_item,
    MAX(IF(event_name = 'add_to_cart', 1, 0)) = 1 AS has_add_to_cart,
    MAX(IF(event_name = 'begin_checkout', 1, 0)) = 1 AS has_begin_checkout,
    MAX(IF(event_name = 'purchase', 1, 0)) = 1 AS has_purchase
  FROM base_events
  WHERE session_id IS NOT NULL
  GROUP BY month, session_id
),
monthly AS (
  SELECT
    month,
    COUNT(DISTINCT session_id) AS sessions,
    COUNT(DISTINCT IF(has_view_item, session_id, NULL)) AS view_item_sessions,
    COUNT(DISTINCT IF(has_view_item AND has_add_to_cart, session_id, NULL)) AS add_to_cart_sessions,
    COUNT(DISTINCT IF(has_view_item AND has_add_to_cart AND has_begin_checkout, session_id, NULL)) AS checkout_sessions,
    COUNT(DISTINCT IF(has_view_item AND has_add_to_cart AND has_begin_checkout AND has_purchase, session_id, NULL)) AS funnel_purchase_sessions,
    COUNT(DISTINCT IF(has_purchase, session_id, NULL)) AS purchase_sessions,
    COUNT(DISTINCT IF(has_begin_checkout AND NOT has_add_to_cart, session_id, NULL)) AS checkout_without_cart_sessions,
    COUNT(DISTINCT IF(has_purchase AND NOT has_begin_checkout, session_id, NULL)) AS purchase_without_checkout_sessions
  FROM session_flags
  GROUP BY month
)
SELECT
  month,
  sessions,
  view_item_sessions,
  add_to_cart_sessions,
  checkout_sessions,
  funnel_purchase_sessions,
  purchase_sessions,
  SAFE_DIVIDE(view_item_sessions, sessions) AS session_to_view_rate,
  SAFE_DIVIDE(add_to_cart_sessions, view_item_sessions) AS view_to_cart_rate,
  SAFE_DIVIDE(checkout_sessions, add_to_cart_sessions) AS cart_to_checkout_rate,
  SAFE_DIVIDE(funnel_purchase_sessions, checkout_sessions) AS checkout_to_purchase_rate,
  SAFE_DIVIDE(funnel_purchase_sessions, sessions) AS funnel_completion_rate,
  SAFE_DIVIDE(purchase_sessions, sessions) AS session_to_purchase_rate,
  checkout_without_cart_sessions,
  purchase_without_checkout_sessions
FROM monthly
ORDER BY month;
