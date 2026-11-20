-- Step 0. Create the ops_ tables if they do not exist yet (runs before the day's transaction:
-- BigQuery does not allow CREATE TABLE inside a multi-statement transaction).
-- Columns are documented in the step that fills each table (01~05).

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_f_orders` (
  order_date DATE,
  order_key STRING,
  transaction_id STRING,
  session_id STRING,
  user_pseudo_id STRING,
  order_ts INT64,
  purchase_revenue FLOAT64,
  item_revenue FLOAT64,
  has_revenue BOOL,
  has_tid BOOL,
  purchase_events INT64,
  device_category STRING,
  country STRING,
  medium STRING,
  loaded_at TIMESTAMP
)
PARTITION BY order_date;

CREATE TABLE IF NOT EXISTS `bigquery-457902.ga4_ops_bi.ops_f_sessions` (
  session_date DATE,
  session_id STRING,
  user_pseudo_id STRING,
  is_new_user BOOL,
  has_view_item BOOL,
  has_add_to_cart BOOL,
  has_begin_checkout BOOL,
  has_purchase_event BOOL,
  orders INT64,
  orders_with_revenue INT64,
  revenue FLOAT64,
  device_category STRING,
  country STRING,
  medium STRING,
  loaded_at TIMESTAMP
)
PARTITION BY session_date;

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
