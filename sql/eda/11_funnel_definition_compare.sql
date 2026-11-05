-- Funnel definition check (Dec 2020): open "reach" funnel vs closed "in-order" funnel per session.
WITH e AS (
  SELECT
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS sid,
    event_name, event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201201' AND '20201231'
    AND event_name IN ('session_start', 'view_item', 'add_to_cart', 'begin_checkout', 'purchase')
),
s AS (
  SELECT sid,
    MIN(IF(event_name = 'view_item', event_timestamp, NULL)) AS t1,
    MIN(IF(event_name = 'add_to_cart', event_timestamp, NULL)) AS t2,
    MIN(IF(event_name = 'begin_checkout', event_timestamp, NULL)) AS t3,
    MIN(IF(event_name = 'purchase', event_timestamp, NULL)) AS t4
  FROM e GROUP BY sid
)
SELECT
  COUNT(*) AS sessions,
  COUNTIF(t1 IS NOT NULL) AS open_view_item,
  COUNTIF(t2 IS NOT NULL) AS open_add_to_cart,
  COUNTIF(t3 IS NOT NULL) AS open_checkout,
  COUNTIF(t4 IS NOT NULL) AS open_purchase,
  COUNTIF(t1 IS NOT NULL AND t2 >= t1) AS closed_add_to_cart,
  COUNTIF(t1 IS NOT NULL AND t2 >= t1 AND t3 >= t2) AS closed_checkout,
  COUNTIF(t1 IS NOT NULL AND t2 >= t1 AND t3 >= t2 AND t4 >= t3) AS closed_purchase,
  COUNTIF(t3 IS NOT NULL AND t2 IS NULL) AS checkout_without_cart,
  COUNTIF(t4 IS NOT NULL AND t3 IS NULL) AS purchase_without_checkout,
  COUNTIF(t4 IS NOT NULL AND t1 IS NULL) AS purchase_without_view_item
FROM s;
