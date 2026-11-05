-- Validate: can session be the dedupe key for purchases?
WITH p AS (
  SELECT event_date, event_timestamp, user_pseudo_id,
    CONCAT(user_pseudo_id,'-',CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key='ga_session_id') AS STRING)) sid,
    NULLIF(ecommerce.transaction_id,'(not set)') tid, ecommerce.purchase_revenue rev
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` WHERE event_name='purchase'
),
dup_tid AS (SELECT tid, COUNT(DISTINCT sid) n_sid FROM p WHERE tid IS NOT NULL GROUP BY tid HAVING COUNT(*)>1),
s AS (
  SELECT sid, COUNT(*) n_evt, COUNTIF(tid IS NULL) n_null_tid, COUNT(DISTINCT tid) n_tid,
    COUNT(DISTINCT CAST(rev AS STRING)) n_rev
  FROM p GROUP BY sid
)
SELECT 'dup_tid_groups' k, COUNT(*) v FROM dup_tid
UNION ALL SELECT 'dup_tid_same_session', COUNTIF(n_sid=1) FROM dup_tid
UNION ALL SELECT 'purchase_events', COUNT(*) FROM p
UNION ALL SELECT 'purchase_sessions', COUNT(*) FROM s
UNION ALL SELECT 'sessions_multi_purchase_evt', COUNTIF(n_evt>1) FROM s
UNION ALL SELECT 'sessions_multi_distinct_tid', COUNTIF(n_tid>1) FROM s
UNION ALL SELECT 'sessions_with_null_tid', COUNTIF(n_null_tid>0) FROM s
UNION ALL SELECT 'sessions_null_tid_multi_evt', COUNTIF(n_null_tid>1) FROM s
UNION ALL SELECT 'sessions_mixed_tid_and_null', COUNTIF(n_null_tid>0 AND n_tid>0) FROM s
UNION ALL SELECT 'orders_dedup_tid_plus_null_events', (SELECT COUNT(DISTINCT tid) FROM p) + (SELECT COUNTIF(tid IS NULL) FROM p)
UNION ALL SELECT 'orders_dedup_tid_plus_null_by_session_rev',
  (SELECT COUNT(DISTINCT tid) FROM p) + (SELECT COUNT(*) FROM (SELECT DISTINCT sid, CAST(rev AS STRING) FROM p WHERE tid IS NULL));
