-- Reconcile orders/revenue across grains with the ops order key:
-- order_key = transaction_id if present, else session_id + revenue
WITH p AS (
  SELECT event_timestamp,
    CONCAT(user_pseudo_id,'-',CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='ga_session_id') AS STRING)) sid,
    NULLIF(ecommerce.transaction_id,'(not set)') tid, ecommerce.purchase_revenue rev
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` WHERE event_name='purchase'
), k AS (
  SELECT *, COALESCE(CONCAT('T:',tid), CONCAT('S:',sid,'|',IFNULL(CAST(rev AS STRING),'null'))) order_key FROM p
), o AS (
  SELECT * FROM k QUALIFY ROW_NUMBER() OVER (PARTITION BY order_key ORDER BY event_timestamp)=1
), s AS (
  SELECT sid, SUM(IFNULL(rev,0)) rev FROM o GROUP BY sid
)
SELECT 'A_event_grain' AS grain, (SELECT COUNT(*) FROM p) AS orders, (SELECT ROUND(SUM(IFNULL(rev,0)),0) FROM p) AS revenue,
  (SELECT COUNTIF(rev IS NULL) FROM p) AS null_rev_orders
UNION ALL SELECT 'B_order_grain_dedup', COUNT(*), ROUND(SUM(IFNULL(rev,0)),0), COUNTIF(rev IS NULL) FROM o
UNION ALL SELECT 'C_session_grain_rollup', COUNT(*), ROUND(SUM(rev),0), NULL FROM s
UNION ALL SELECT 'D_orders_with_tid', COUNTIF(tid IS NOT NULL), ROUND(SUM(IF(tid IS NOT NULL,IFNULL(rev,0),0)),0), COUNTIF(tid IS NOT NULL AND rev IS NULL) FROM o
UNION ALL SELECT 'E_orders_without_tid', COUNTIF(tid IS NULL), ROUND(SUM(IF(tid IS NULL,IFNULL(rev,0),0)),0), COUNTIF(tid IS NULL AND rev IS NULL) FROM o
ORDER BY grain;
