-- Raw GA4 overview: period, volume, identifiers
SELECT
  MIN(event_date) AS min_date,
  MAX(event_date) AS max_date,
  COUNT(DISTINCT event_date) AS days,
  COUNT(*) AS events,
  COUNT(DISTINCT event_name) AS event_types,
  COUNT(DISTINCT user_pseudo_id) AS users,
  COUNT(DISTINCT CONCAT(user_pseudo_id, CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='ga_session_id') AS STRING))) AS sessions,
  COUNTIF(event_name='purchase') AS purchase_events,
  COUNT(DISTINCT IF(event_name='purchase', ecommerce.transaction_id, NULL)) AS distinct_transaction_ids,
  ROUND(SUM(IF(event_name='purchase', ecommerce.purchase_revenue, 0)),2) AS purchase_revenue,
  COUNT(DISTINCT platform) AS platforms,
  STRING_AGG(DISTINCT platform) AS platform_list
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`;
