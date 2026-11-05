-- Daily values of each data-quality check over all 92 days, to set thresholds from the normal range.
WITH e AS (
  SELECT PARSE_DATE('%Y%m%d', event_date) AS d, event_name, event_timestamp,
    CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)) AS sid,
    NULLIF(ecommerce.transaction_id, '(not set)') AS tid, ecommerce.purchase_revenue AS rev,
    (SELECT SUM(i.item_revenue) FROM UNNEST(items) i) AS item_rev
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
),
p AS (
  SELECT *, COALESCE(CONCAT('T:', tid), CONCAT('S:', sid, '|', IFNULL(CAST(rev AS STRING), 'null'))) AS k FROM e WHERE event_name = 'purchase'
),
o AS (SELECT * FROM p WHERE TRUE QUALIFY ROW_NUMBER() OVER (PARTITION BY k ORDER BY event_timestamp) = 1),
day_s AS (
  SELECT d, COUNT(DISTINCT sid) AS sessions,
    COUNT(DISTINCT IF(event_name = 'add_to_cart', sid, NULL)) AS cart_s,
    COUNT(DISTINCT IF(event_name = 'begin_checkout', sid, NULL)) AS checkout_s
  FROM e GROUP BY d
),
day_p AS (SELECT d, COUNT(*) AS purchase_events FROM p GROUP BY d),
day_o AS (
  SELECT d, COUNT(*) AS orders, COUNTIF(rev IS NULL) AS null_rev, COUNTIF(tid IS NULL) AS no_tid,
    COUNTIF(rev > 0 AND ABS(IFNULL(item_rev, 0) - rev) / rev > 0.01) AS mismatch, COUNTIF(rev > 0) AS rev_orders
  FROM o GROUP BY d
)
SELECT s.d,
  ROUND(SAFE_DIVIDE(s.sessions, LAG(s.sessions, 7) OVER (ORDER BY s.d)) - 1, 3) AS dq02_session_wow,
  ROUND(SAFE_DIVIDE(o.null_rev, o.orders), 3) AS dq03_null_rev,
  ROUND(SAFE_DIVIDE(p.purchase_events - o.orders, p.purchase_events), 3) AS dq04_dup,
  ROUND(SAFE_DIVIDE(o.no_tid, o.orders), 3) AS dq05_missing_tid,
  ROUND(SAFE_DIVIDE(o.mismatch, o.rev_orders), 3) AS dq06_mismatch,
  ROUND(SAFE_DIVIDE(s.cart_s, s.checkout_s), 3) AS dq08_cart_to_checkout
FROM day_s s JOIN day_p p USING (d) JOIN day_o o USING (d)
ORDER BY s.d;
