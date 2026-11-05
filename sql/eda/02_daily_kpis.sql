-- Daily KPI time series from raw events (session = user_pseudo_id + ga_session_id)
WITH e AS (
  SELECT PARSE_DATE('%Y%m%d', event_date) AS d, event_name, user_pseudo_id,
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='ga_session_id') AS STRING)) AS sid,
    ecommerce.transaction_id AS tid, ecommerce.purchase_revenue AS rev
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
)
SELECT d, FORMAT_DATE('%a', d) AS dow,
  COUNT(*) AS events,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT sid) AS sessions,
  COUNT(DISTINCT IF(event_name='view_item', sid, NULL)) AS view_item_sessions,
  COUNT(DISTINCT IF(event_name='add_to_cart', sid, NULL)) AS add_to_cart_sessions,
  COUNT(DISTINCT IF(event_name='begin_checkout', sid, NULL)) AS checkout_sessions,
  COUNT(DISTINCT IF(event_name='purchase', sid, NULL)) AS purchase_sessions,
  COUNTIF(event_name='purchase') AS purchase_events,
  COUNT(DISTINCT IF(event_name='purchase', user_pseudo_id, NULL)) AS buyers,
  ROUND(SUM(IF(event_name='purchase', rev, 0)),2) AS revenue
FROM e GROUP BY 1,2 ORDER BY 1;
