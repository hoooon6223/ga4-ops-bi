-- Null-revenue purchases: do they carry item revenue / tid?
SELECT
  COUNTIF(ecommerce.purchase_revenue IS NULL) null_rev,
  COUNTIF(ecommerce.purchase_revenue IS NULL AND (ecommerce.transaction_id IS NULL OR ecommerce.transaction_id='(not set)')) null_rev_and_no_tid,
  ROUND(SUM(IF(ecommerce.purchase_revenue IS NULL,(SELECT SUM(i.item_revenue) FROM UNNEST(items) i),0)),0) item_rev_on_null_rev,
  MIN(IF(ecommerce.purchase_revenue IS NULL,event_date,NULL)) first_d, MAX(IF(ecommerce.purchase_revenue IS NULL,event_date,NULL)) last_d,
  COUNT(DISTINCT IF(ecommerce.purchase_revenue IS NULL,event_date,NULL)) days_with_null
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` WHERE event_name='purchase';
