-- Step 4. DoD / WoW / rolling-7d / MoM comparison for @run_date, one row per metric.
-- Definitions & thresholds: docs/ops_bi/02_ops_metric_definitions.md §3, §4, §7
--   count metrics : change = current / previous - 1   (threshold is a fraction, 0.25 = 25%)
--   rate metrics  : change = (current - previous) * 100 (threshold is in %p)
-- A window with missing days returns NULL (no comparison) instead of a misleading number.

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_kpi_comparison` (
  kpi_date DATE,
  tier INT64,
  metric_id STRING,
  metric_name STRING,
  unit STRING,
  flag_basis STRING,
  threshold FLOAT64,
  value_day FLOAT64,
  prev_day FLOAT64,
  dod_change FLOAT64,
  same_dow_last_week FLOAT64,
  wow_day_change FLOAT64,
  r7_value FLOAT64,
  r7_prev FLOAT64,
  r7_change FLOAT64,
  mtd_value FLOAT64,
  mtd_prev_month FLOAT64,
  mom_change FLOAT64,
  flag_change FLOAT64,
  flag STRING,
  loaded_at TIMESTAMP
)
PARTITION BY kpi_date;

DELETE FROM `bigquery-457902.ga4_ops_bi.ops_kpi_comparison` WHERE kpi_date = @run_date;

INSERT INTO `bigquery-457902.ga4_ops_bi.ops_kpi_comparison`
WITH cfg AS (
  SELECT * FROM UNNEST([
    STRUCT(1 AS tier, 'K01_revenue' AS metric_id, '매출' AS metric_name, 'count' AS unit, 'r7_wow' AS flag_basis, 0.25 AS threshold),
    (1, 'K02_orders', '주문 수', 'count', 'r7_wow', 0.25),
    (1, 'K03_sessions', '세션', 'count', 'day_wow', 0.20),
    (1, 'K04_active_users', '활성 사용자', 'count', 'day_wow', 0.20),
    (1, 'K05_session_cvr', '세션 전환율', 'rate', 'r7_wow', 0.20),
    (1, 'K06_aov', '객단가', 'count', 'r7_wow', 0.15),
    (2, 'D01_view_item_rate', '상품 조회율', 'rate', 'r7_wow', 2.0),
    (2, 'D02_add_to_cart_rate', '장바구니율', 'rate', 'r7_wow', 2.0),
    (2, 'D03_checkout_rate', '체크아웃 진입률', 'rate', 'r7_wow', 5.0),
    (2, 'D04_purchase_completion_rate', '결제 완료율', 'rate', 'r7_wow', 5.0),
    (2, 'D05_new_user_share', '신규 사용자 비중', 'rate', 'r7_wow', 5.0)
  ])
),
win AS (
  SELECT * FROM UNNEST([
    STRUCT('cur' AS w, @run_date AS s, @run_date AS e),
    ('dod', DATE_SUB(@run_date, INTERVAL 1 DAY), DATE_SUB(@run_date, INTERVAL 1 DAY)),
    ('wow', DATE_SUB(@run_date, INTERVAL 7 DAY), DATE_SUB(@run_date, INTERVAL 7 DAY)),
    ('r7', DATE_SUB(@run_date, INTERVAL 6 DAY), @run_date),
    ('r7p', DATE_SUB(@run_date, INTERVAL 13 DAY), DATE_SUB(@run_date, INTERVAL 7 DAY)),
    ('mtd', DATE_TRUNC(@run_date, MONTH), @run_date),
    ('mtdp', DATE_SUB(DATE_TRUNC(@run_date, MONTH), INTERVAL 1 MONTH), DATE_SUB(@run_date, INTERVAL 1 MONTH))
  ])
),
agg AS (
  SELECT
    win.w,
    COUNT(k.kpi_date) = DATE_DIFF(win.e, win.s, DAY) + 1 AS complete,
    SUM(k.revenue) AS revenue,
    SUM(k.orders) AS orders,
    SUM(k.sessions) AS sessions,
    SUM(k.active_users) AS active_users,
    SUM(k.new_users) AS new_users,
    SUM(k.order_sessions) AS order_sessions,
    SUM(k.orders_with_revenue) AS orders_with_revenue,
    SUM(k.view_item_sessions) AS view_item_sessions,
    SUM(k.add_to_cart_sessions) AS add_to_cart_sessions,
    SUM(k.checkout_sessions) AS checkout_sessions
  FROM win
  LEFT JOIN `bigquery-457902.ga4_ops_bi.ops_kpi_daily` AS k
    ON k.kpi_date BETWEEN win.s AND win.e
  GROUP BY win.w, win.s, win.e
),
m AS (
  SELECT
    agg.w,
    x.metric_id,
    IF(agg.complete, x.val, NULL) AS val
  FROM agg,
  UNNEST([
    STRUCT('K01_revenue' AS metric_id, CAST(revenue AS FLOAT64) AS val),
    ('K02_orders', CAST(orders AS FLOAT64)),
    ('K03_sessions', CAST(sessions AS FLOAT64)),
    ('K04_active_users', CAST(active_users AS FLOAT64)),
    ('K05_session_cvr', SAFE_DIVIDE(order_sessions, sessions)),
    ('K06_aov', SAFE_DIVIDE(revenue, orders_with_revenue)),
    ('D01_view_item_rate', SAFE_DIVIDE(view_item_sessions, sessions)),
    ('D02_add_to_cart_rate', SAFE_DIVIDE(add_to_cart_sessions, view_item_sessions)),
    ('D03_checkout_rate', SAFE_DIVIDE(checkout_sessions, add_to_cart_sessions)),
    ('D04_purchase_completion_rate', SAFE_DIVIDE(order_sessions, checkout_sessions)),
    ('D05_new_user_share', SAFE_DIVIDE(new_users, active_users))
  ]) AS x
),
wide AS (
  SELECT
    metric_id,
    MAX(IF(w = 'cur', val, NULL)) AS value_day,
    MAX(IF(w = 'dod', val, NULL)) AS prev_day,
    MAX(IF(w = 'wow', val, NULL)) AS same_dow_last_week,
    MAX(IF(w = 'r7', val, NULL)) AS r7_value,
    MAX(IF(w = 'r7p', val, NULL)) AS r7_prev,
    MAX(IF(w = 'mtd', val, NULL)) AS mtd_value,
    MAX(IF(w = 'mtdp', val, NULL)) AS mtd_prev_month
  FROM m
  GROUP BY metric_id
),
chg AS (
  SELECT
    cfg.*,
    wide.* EXCEPT (metric_id),
    IF(cfg.unit = 'rate', (value_day - prev_day) * 100, SAFE_DIVIDE(value_day, prev_day) - 1) AS dod_change,
    IF(cfg.unit = 'rate', (value_day - same_dow_last_week) * 100, SAFE_DIVIDE(value_day, same_dow_last_week) - 1) AS wow_day_change,
    IF(cfg.unit = 'rate', (r7_value - r7_prev) * 100, SAFE_DIVIDE(r7_value, r7_prev) - 1) AS r7_change,
    IF(cfg.unit = 'rate', (mtd_value - mtd_prev_month) * 100, SAFE_DIVIDE(mtd_value, mtd_prev_month) - 1) AS mom_change
  FROM cfg
  JOIN wide USING (metric_id)
)
SELECT
  @run_date AS kpi_date,
  tier,
  metric_id,
  metric_name,
  unit,
  flag_basis,
  threshold,
  value_day,
  prev_day,
  dod_change,
  same_dow_last_week,
  wow_day_change,
  r7_value,
  r7_prev,
  r7_change,
  mtd_value,
  mtd_prev_month,
  mom_change,
  IF(flag_basis = 'day_wow', wow_day_change, r7_change) AS flag_change,
  CASE
    WHEN IF(flag_basis = 'day_wow', wow_day_change, r7_change) IS NULL THEN 'n/a'
    WHEN ABS(IF(flag_basis = 'day_wow', wow_day_change, r7_change)) > threshold THEN 'notable'
    ELSE 'normal'
  END AS flag,
  CURRENT_TIMESTAMP() AS loaded_at
FROM chg;
