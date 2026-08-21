-- daily_kpi_mart 검증 쿼리
--
-- 목적:
-- 1. daily_kpi_mart의 grain과 기간을 확인한다.
-- 2. daily mart를 월 단위로 집계할 때 어떤 지표를 단순 합산해도 되는지 확인한다.
-- 3. distinct 지표(users, purchasers, sessions)는 기간 집계에서 재집계가 필요함을 검증한다.

-- 1. daily_kpi_mart 기본 확인
SELECT
  COUNT(*) AS row_count,
  MIN(date) AS min_date,
  MAX(date) AS max_date,
  SUM(sessions) AS sum_daily_sessions,
  SUM(users) AS sum_daily_users_warning,
  SUM(orders) AS orders,
  SUM(revenue) AS revenue
FROM `bigquery-457902.ga4_ops_bi.daily_kpi_mart`;

-- 2. daily_kpi_mart를 월 단위로 집계
-- 주의:
-- sessions, users, purchasers, purchase_sessions는 distinct 기반 지표라
-- 월/분기/전체 기간 단위에서는 raw event에서 다시 distinct count하는 것이 가장 엄밀하다.
-- orders와 revenue는 현재 정의상 합산 가능하다.
SELECT
  DATE_TRUNC(date, MONTH) AS month,
  SUM(sessions) AS sum_daily_sessions,
  SUM(purchase_sessions) AS sum_daily_purchase_sessions,
  SUM(orders) AS orders,
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(purchase_sessions), SUM(sessions)) AS approx_session_cvr,
  SAFE_DIVIDE(SUM(revenue), SUM(orders)) AS aov,
  SAFE_DIVIDE(SUM(revenue), SUM(sessions)) AS approx_revenue_per_session
FROM `bigquery-457902.ga4_ops_bi.daily_kpi_mart`
GROUP BY month
ORDER BY month;

-- 3. raw event 월집계와 daily mart 월집계 비교
WITH raw_monthly AS (
  SELECT
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), MONTH) AS month,
    COUNT(DISTINCT CONCAT(
      user_pseudo_id,
      '-',
      CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
    )) AS raw_distinct_sessions,
    COUNT(DISTINCT user_pseudo_id) AS raw_distinct_users,
    COUNT(DISTINCT IF(event_name = 'purchase', user_pseudo_id, NULL)) AS raw_purchasers,
    COUNT(DISTINCT IF(
      event_name = 'purchase',
      CONCAT(
        user_pseudo_id,
        '-',
        CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
      ),
      NULL
    )) AS raw_purchase_sessions,
    COUNTIF(event_name = 'purchase') AS raw_orders,
    SUM(IF(event_name = 'purchase', ecommerce.purchase_revenue, 0)) AS raw_revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY month
),
mart_monthly AS (
  SELECT
    DATE_TRUNC(date, MONTH) AS month,
    SUM(sessions) AS mart_sum_daily_sessions,
    SUM(users) AS mart_sum_daily_users,
    SUM(purchasers) AS mart_sum_daily_purchasers,
    SUM(purchase_sessions) AS mart_sum_daily_purchase_sessions,
    SUM(orders) AS mart_orders,
    SUM(revenue) AS mart_revenue
  FROM `bigquery-457902.ga4_ops_bi.daily_kpi_mart`
  GROUP BY month
)
SELECT
  r.month,
  r.raw_distinct_sessions,
  m.mart_sum_daily_sessions,
  m.mart_sum_daily_sessions - r.raw_distinct_sessions AS session_diff,
  r.raw_distinct_users,
  m.mart_sum_daily_users,
  r.raw_purchasers,
  m.mart_sum_daily_purchasers,
  r.raw_purchase_sessions,
  m.mart_sum_daily_purchase_sessions,
  m.mart_sum_daily_purchase_sessions - r.raw_purchase_sessions AS purchase_session_diff,
  r.raw_orders,
  m.mart_orders,
  r.raw_revenue,
  m.mart_revenue
FROM raw_monthly r
JOIN mart_monthly m USING (month)
ORDER BY month;

