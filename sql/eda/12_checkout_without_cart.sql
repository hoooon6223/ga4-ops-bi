-- Checkout sessions with no add_to_cart in the same session (Dec 2020):
-- did the user add to cart in an earlier session (cart carried over), or never (direct buy / tracking gap)?
WITH e AS (
  SELECT user_pseudo_id AS uid,
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS sid,
    event_name, event_timestamp AS t
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201125' AND '20201231'   -- a few days of lookback for earlier carts
    AND event_name IN ('view_item', 'add_to_cart', 'begin_checkout', 'purchase')
),
s AS (
  SELECT uid, sid,
    MIN(IF(event_name = 'begin_checkout', t, NULL)) AS t_checkout,
    LOGICAL_OR(event_name = 'add_to_cart') AS has_cart,
    LOGICAL_OR(event_name = 'view_item') AS has_view,
    LOGICAL_OR(event_name = 'purchase') AS has_purchase
  FROM e GROUP BY uid, sid
),
target AS (
  SELECT * FROM s
  WHERE t_checkout IS NOT NULL AND NOT has_cart
    AND DATE(TIMESTAMP_MICROS(t_checkout)) BETWEEN '2020-12-01' AND '2020-12-31'
)
SELECT
  COUNT(*) AS checkout_without_cart,
  COUNTIF(EXISTS(SELECT 1 FROM e WHERE e.uid = target.uid AND e.event_name = 'add_to_cart' AND e.t < target.t_checkout)) AS earlier_cart_same_user,
  COUNTIF(has_view) AS viewed_item_in_session,
  COUNTIF(has_purchase) AS purchased_in_session
FROM target;
