-- Data quality profile on raw events
WITH e AS (
  SELECT event_date, event_name, user_pseudo_id,
    (SELECT value.int_value FROM UNNEST(event_params) WHERE key='ga_session_id') AS ga_session_id,
    ecommerce.transaction_id AS tid, ecommerce.purchase_revenue AS rev,
    (SELECT SUM(i.item_revenue) FROM UNNEST(items) i) AS item_rev_sum,
    ARRAY_LENGTH(items) AS n_items
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
), p AS (SELECT * FROM e WHERE event_name='purchase')
SELECT 'events_null_user' AS chk, COUNTIF(user_pseudo_id IS NULL) AS n, COUNT(*) AS base FROM e
UNION ALL SELECT 'events_null_ga_session_id', COUNTIF(ga_session_id IS NULL), COUNT(*) FROM e
UNION ALL SELECT 'purchase_tid_null_or_notset', COUNTIF(tid IS NULL OR tid='(not set)'), COUNT(*) FROM p
UNION ALL SELECT 'purchase_rev_null', COUNTIF(rev IS NULL), COUNT(*) FROM p
UNION ALL SELECT 'purchase_rev_zero', COUNTIF(rev = 0), COUNT(*) FROM p
UNION ALL SELECT 'purchase_rev_negative', COUNTIF(rev < 0), COUNT(*) FROM p
UNION ALL SELECT 'purchase_no_items', COUNTIF(IFNULL(n_items,0)=0), COUNT(*) FROM p
UNION ALL SELECT 'purchase_item_rev_mismatch_gt1pct', COUNTIF(rev>0 AND ABS(IFNULL(item_rev_sum,0)-rev)/rev>0.01), COUNTIF(rev>0) FROM p
UNION ALL SELECT 'purchase_dup_tid_rows', (SELECT IFNULL(SUM(c),0) FROM (SELECT COUNT(*) c FROM p WHERE tid IS NOT NULL AND tid!='(not set)' GROUP BY tid HAVING c>1)), COUNT(*) FROM p
UNION ALL SELECT 'purchase_dup_tid_distinct', (SELECT COUNT(*) FROM (SELECT tid FROM p WHERE tid IS NOT NULL AND tid!='(not set)' GROUP BY tid HAVING COUNT(*)>1)), COUNT(*) FROM p
UNION ALL SELECT 'purchase_dup_tid_multi_day', (SELECT COUNT(*) FROM (SELECT tid FROM p WHERE tid IS NOT NULL AND tid!='(not set)' GROUP BY tid HAVING COUNT(DISTINCT event_date)>1)), COUNT(*) FROM p;
