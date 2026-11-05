-- Step 5. Data-quality checks (DQ01~DQ07) and reconciliation rules (R1~R5) for @run_date.
-- Definitions & thresholds: docs/ops_bi/02_ops_metric_definitions.md §5, §6
-- status: PASS / WARN / FAIL / SKIP (comparison window not available yet)

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_dq_results` (
  dq_date DATE,
  check_id STRING,
  check_name STRING,
  value FLOAT64,
  threshold STRING,
  status STRING,
  detail STRING,
  loaded_at TIMESTAMP
)
PARTITION BY dq_date;

DELETE FROM `bigquery-457902.ga4_ops_bi.ops_dq_results` WHERE dq_date = @run_date;

INSERT INTO `bigquery-457902.ga4_ops_bi.ops_dq_results`
WITH k AS (
  SELECT * FROM `bigquery-457902.ga4_ops_bi.ops_kpi_daily` WHERE kpi_date = @run_date
),
lw AS (
  SELECT sessions FROM `bigquery-457902.ga4_ops_bi.ops_kpi_daily` WHERE kpi_date = DATE_SUB(@run_date, INTERVAL 7 DAY)
),
r7 AS (
  SELECT COUNT(*) AS n, SUM(orders) AS orders, SUM(revenue) AS revenue
  FROM `bigquery-457902.ga4_ops_bi.ops_kpi_daily`
  WHERE kpi_date BETWEEN DATE_SUB(@run_date, INTERVAL 6 DAY) AND @run_date
),
r7p AS (
  SELECT COUNT(*) AS n, SUM(orders) AS orders, SUM(revenue) AS revenue
  FROM `bigquery-457902.ga4_ops_bi.ops_kpi_daily`
  WHERE kpi_date BETWEEN DATE_SUB(@run_date, INTERVAL 13 DAY) AND DATE_SUB(@run_date, INTERVAL 7 DAY)
),
v AS (
  SELECT
    k.*,
    SAFE_DIVIDE(k.sessions, (SELECT sessions FROM lw)) - 1 AS session_wow,
    SAFE_DIVIDE(k.null_revenue_orders, k.orders) AS null_rev_rate,
    SAFE_DIVIDE(k.purchase_events - k.orders, k.purchase_events) AS dup_rate,
    SAFE_DIVIDE(k.orders_without_tid, k.orders) AS missing_tid_rate,
    SAFE_DIVIDE(k.item_mismatch_orders, k.orders_with_positive_revenue) AS item_mismatch_rate,
    IF(r7.n = 7 AND r7p.n = 7, SAFE_DIVIDE(r7.orders, r7p.orders) - 1, NULL) AS orders_r7_wow,
    IF(r7.n = 7 AND r7p.n = 7, SAFE_DIVIDE(r7.revenue, r7p.revenue) - 1, NULL) AS revenue_r7_wow
  FROM k, r7, r7p
),
checks AS (
  SELECT 'DQ01_arrival' AS check_id, '데이터 도착' AS check_name, CAST(events AS FLOAT64) AS value, '> 0' AS threshold,
    IF(events > 0, 'PASS', 'FAIL') AS status, FORMAT('events=%d', events) AS detail FROM v
  UNION ALL
  SELECT 'DQ02_session_spike', '세션 급변 (같은 요일 대비)', session_wow, '|change| <= 0.40',
    CASE WHEN session_wow IS NULL THEN 'SKIP' WHEN ABS(session_wow) > 0.40 THEN 'WARN' ELSE 'PASS' END,
    FORMAT('sessions=%d', sessions) FROM v
  UNION ALL
  SELECT 'DQ03_null_revenue', '매출 누락률', null_rev_rate, 'WARN > 0.10, FAIL > 0.30',
    CASE WHEN null_rev_rate IS NULL THEN 'SKIP' WHEN null_rev_rate > 0.30 THEN 'FAIL' WHEN null_rev_rate > 0.10 THEN 'WARN' ELSE 'PASS' END,
    FORMAT('null_revenue_orders=%d / orders=%d', null_revenue_orders, orders) FROM v
  UNION ALL
  SELECT 'DQ04_dup_orders', '주문 중복률', dup_rate, '<= 0.15',
    CASE WHEN dup_rate IS NULL THEN 'SKIP' WHEN dup_rate > 0.15 THEN 'WARN' ELSE 'PASS' END,
    FORMAT('purchase_events=%d, orders=%d', purchase_events, orders) FROM v
  UNION ALL
  SELECT 'DQ05_missing_tid', '거래번호 누락률', missing_tid_rate, '<= 0.20',
    CASE WHEN missing_tid_rate IS NULL THEN 'SKIP' WHEN missing_tid_rate > 0.20 THEN 'WARN' ELSE 'PASS' END,
    FORMAT('orders_without_tid=%d', orders_without_tid) FROM v
  UNION ALL
  SELECT 'DQ06_item_reconcile', '주문 매출 vs 상품 매출 불일치 비중', item_mismatch_rate, '<= 0.20',
    CASE WHEN item_mismatch_rate IS NULL THEN 'SKIP' WHEN item_mismatch_rate > 0.20 THEN 'WARN' ELSE 'PASS' END,
    FORMAT('mismatch=%d / orders_with_revenue=%d', item_mismatch_orders, orders_with_positive_revenue) FROM v
  UNION ALL
  SELECT 'DQ07_order_revenue_gap', '주문-매출 괴리 (rolling 7d)', revenue_r7_wow, 'FAIL if |orders wow| <= 0.20 and revenue wow <= -0.50',
    CASE WHEN revenue_r7_wow IS NULL OR orders_r7_wow IS NULL THEN 'SKIP'
         WHEN ABS(orders_r7_wow) <= 0.20 AND revenue_r7_wow <= -0.50 THEN 'FAIL' ELSE 'PASS' END,
    FORMAT('orders_r7_wow=%s, revenue_r7_wow=%s',
      IFNULL(FORMAT('%.3f', orders_r7_wow), 'null'), IFNULL(FORMAT('%.3f', revenue_r7_wow), 'null')) FROM v
  UNION ALL
  SELECT 'DQ08_funnel_tracking', '장바구니 수집 정합성 (장바구니 >= 체크아웃)', SAFE_DIVIDE(add_to_cart_sessions, checkout_sessions), '>= 1.0',
    CASE WHEN checkout_sessions = 0 THEN 'SKIP' WHEN add_to_cart_sessions < checkout_sessions THEN 'WARN' ELSE 'PASS' END,
    FORMAT('add_to_cart_sessions=%d, checkout_sessions=%d', add_to_cart_sessions, checkout_sessions) FROM v
  UNION ALL
  SELECT 'R1_events_to_orders', '주문 수 <= purchase 이벤트 수', CAST(orders AS FLOAT64), FORMAT('<= %d', purchase_events),
    IF(orders <= purchase_events, 'PASS', 'FAIL'), FORMAT('orders=%d, purchase_events=%d', orders, purchase_events) FROM v
  UNION ALL
  SELECT 'R2_order_session_rollup', '주문 = 세션 합산 (건수·매출)', revenue - session_revenue, 'diff = 0',
    IF(orders = session_orders AND ABS(revenue - session_revenue) < 0.01, 'PASS', 'FAIL'),
    FORMAT('orders=%d vs %d, revenue=%.2f vs %.2f', orders, session_orders, revenue, session_revenue) FROM v
  UNION ALL
  SELECT 'R3_order_sessions', '주문 세션 수 <= 원본 purchase 세션 수', CAST(order_sessions AS FLOAT64), FORMAT('<= %d', raw_purchase_sessions),
    IF(order_sessions <= raw_purchase_sessions, 'PASS', 'FAIL'), FORMAT('order_sessions=%d, raw_purchase_sessions=%d', order_sessions, raw_purchase_sessions) FROM v
  UNION ALL
  SELECT 'R5_dedup_revenue', '중복 제거 매출 <= 원본 매출', revenue, FORMAT('<= %.2f', raw_revenue),
    IF(revenue <= raw_revenue + 0.01, 'PASS', 'FAIL'), FORMAT('revenue=%.2f, raw_revenue=%.2f', revenue, raw_revenue) FROM v
)
SELECT
  @run_date AS dq_date,
  check_id,
  check_name,
  value,
  threshold,
  status,
  detail,
  CURRENT_TIMESTAMP() AS loaded_at
FROM checks;
