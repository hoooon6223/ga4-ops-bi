-- Looker Studio dataset: current_month_kpi_mart
-- Grain: one row for the selected issue month.
-- Purpose: stable scorecards for January 2021 vs December 2020.

CREATE OR REPLACE TABLE `bigquery-457902.ga4_ops_bi.current_month_kpi_mart` AS
WITH monthly AS (
  SELECT *
  FROM `bigquery-457902.ga4_ops_bi.monthly_kpi_mart`
),
current_period AS (
  SELECT *
  FROM monthly
  WHERE month = DATE '2021-01-01'
),
previous_period AS (
  SELECT *
  FROM monthly
  WHERE month = DATE '2020-12-01'
)
SELECT
  c.month AS current_month,
  p.month AS comparison_month,
  c.revenue,
  SAFE_DIVIDE(c.revenue - p.revenue, p.revenue) AS revenue_mom_pct,
  c.sessions,
  SAFE_DIVIDE(c.sessions - p.sessions, p.sessions) AS sessions_mom_pct,
  c.session_cvr,
  c.session_cvr - p.session_cvr AS session_cvr_mom_point,
  c.aov,
  SAFE_DIVIDE(c.aov - p.aov, p.aov) AS aov_mom_pct,
  c.revenue_per_session,
  SAFE_DIVIDE(c.revenue_per_session - p.revenue_per_session, p.revenue_per_session) AS revenue_per_session_mom_pct,
  c.orders,
  SAFE_DIVIDE(c.orders - p.orders, p.orders) AS orders_mom_pct
FROM current_period c
CROSS JOIN previous_period p;

