-- Step 3. Daily base counts for @run_date.
-- Stores numerators/denominators (not ratios) so rolling 7d / MTD windows can be summed correctly.
-- Raw-event counts are kept next to deduped counts for data-quality checks and reconciliation.

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_kpi_daily` (
  kpi_date DATE,
  sessions INT64,                    -- K03
  active_users INT64,                -- K04 (DAU)
  new_users INT64,                   -- D05 numerator
  order_sessions INT64,              -- K05 numerator
  orders INT64,                      -- K02
  orders_with_revenue INT64,         -- K06 denominator
  revenue FLOAT64,                   -- K01
  buyers INT64,                      -- D06 denominator
  view_item_sessions INT64,          -- D01
  add_to_cart_sessions INT64,        -- D02
  checkout_sessions INT64,           -- D03
  session_orders INT64,              -- R2: orders rolled up from sessions
  session_revenue FLOAT64,           -- R2: revenue rolled up from sessions
  orders_without_tid INT64,          -- DQ05
  null_revenue_orders INT64,         -- DQ03
  item_mismatch_orders INT64,        -- DQ06 numerator
  orders_with_positive_revenue INT64,-- DQ06 denominator
  events INT64,                      -- DQ01 (raw)
  purchase_events INT64,             -- DQ04, R1 (raw)
  raw_purchase_sessions INT64,       -- R3 (raw)
  raw_revenue FLOAT64,               -- R5 (raw)
  loaded_at TIMESTAMP
)
PARTITION BY kpi_date;

DELETE FROM `bigquery-457902.ga4_ops_bi.ops_kpi_daily` WHERE kpi_date = @run_date;

INSERT INTO `bigquery-457902.ga4_ops_bi.ops_kpi_daily`
WITH s AS (
  SELECT * FROM `bigquery-457902.ga4_ops_bi.ops_f_sessions` WHERE session_date = @run_date
),
o AS (
  SELECT * FROM `bigquery-457902.ga4_ops_bi.ops_f_orders` WHERE order_date = @run_date
),
raw AS (
  SELECT
    COUNT(*) AS events,
    COUNTIF(event_name = 'purchase') AS purchase_events,
    COUNT(DISTINCT IF(
      event_name = 'purchase',
      CONCAT(user_pseudo_id, '-', CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)),
      NULL
    )) AS raw_purchase_sessions,
    IFNULL(SUM(IF(event_name = 'purchase', IFNULL(ecommerce.purchase_revenue, 0), 0)), 0) AS raw_revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX = FORMAT_DATE('%Y%m%d', @run_date)
),
s_agg AS (
  SELECT
    COUNT(*) AS sessions,
    COUNT(DISTINCT user_pseudo_id) AS active_users,
    COUNT(DISTINCT IF(is_new_user, user_pseudo_id, NULL)) AS new_users,
    COUNTIF(orders > 0) AS order_sessions,
    COUNTIF(has_view_item) AS view_item_sessions,
    COUNTIF(has_add_to_cart) AS add_to_cart_sessions,
    COUNTIF(has_begin_checkout) AS checkout_sessions,
    IFNULL(SUM(orders), 0) AS session_orders,
    IFNULL(SUM(revenue), 0) AS session_revenue
  FROM s
),
o_agg AS (
  SELECT
    COUNT(*) AS orders,
    COUNTIF(has_revenue) AS orders_with_revenue,
    IFNULL(SUM(IFNULL(purchase_revenue, 0)), 0) AS revenue,
    COUNT(DISTINCT user_pseudo_id) AS buyers,
    COUNTIF(NOT has_tid) AS orders_without_tid,
    COUNTIF(NOT has_revenue) AS null_revenue_orders,
    COUNTIF(purchase_revenue > 0 AND ABS(IFNULL(item_revenue, 0) - purchase_revenue) / purchase_revenue > 0.01) AS item_mismatch_orders,
    COUNTIF(purchase_revenue > 0) AS orders_with_positive_revenue
  FROM o
)
SELECT
  @run_date AS kpi_date,
  s_agg.sessions,
  s_agg.active_users,
  s_agg.new_users,
  s_agg.order_sessions,
  o_agg.orders,
  o_agg.orders_with_revenue,
  o_agg.revenue,
  o_agg.buyers,
  s_agg.view_item_sessions,
  s_agg.add_to_cart_sessions,
  s_agg.checkout_sessions,
  s_agg.session_orders,
  s_agg.session_revenue,
  o_agg.orders_without_tid,
  o_agg.null_revenue_orders,
  o_agg.item_mismatch_orders,
  o_agg.orders_with_positive_revenue,
  raw.events,
  raw.purchase_events,
  raw.raw_purchase_sessions,
  raw.raw_revenue,
  CURRENT_TIMESTAMP() AS loaded_at
FROM raw, s_agg, o_agg;
