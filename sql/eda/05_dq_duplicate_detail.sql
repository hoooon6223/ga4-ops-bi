-- Are duplicated transaction_ids exact re-sends or different orders?
WITH p AS (
  SELECT event_date, event_timestamp, user_pseudo_id, ecommerce.transaction_id AS tid,
    ecommerce.purchase_revenue AS rev, ARRAY_LENGTH(items) n_items
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE event_name='purchase' AND ecommerce.transaction_id IS NOT NULL AND ecommerce.transaction_id!='(not set)'
), g AS (
  SELECT tid, COUNT(*) c, COUNT(DISTINCT user_pseudo_id) users, COUNT(DISTINCT rev) revs,
    COUNTIF(rev IS NULL) null_revs, (MAX(event_timestamp)-MIN(event_timestamp))/1e6/60 AS span_min,
    SUM(IFNULL(rev,0)) sum_rev, MAX(IFNULL(rev,0)) max_rev
  FROM p GROUP BY tid HAVING c>1
)
SELECT
  COUNT(*) dup_tids,
  COUNTIF(users=1) same_user, COUNTIF(users>1) diff_users,
  COUNTIF(revs<=1) same_rev_or_one_null,
  COUNTIF(span_min<=10) within_10min,
  ROUND(SUM(sum_rev-max_rev),0) AS revenue_overcount_if_summed,
  (SELECT ROUND(SUM(IFNULL(rev,0)),0) FROM p) AS total_rev_with_tid
FROM g;
