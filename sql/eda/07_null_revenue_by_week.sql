-- Share of purchase events missing revenue/transaction_id by week
SELECT DATE_TRUNC(PARSE_DATE('%Y%m%d',event_date), WEEK(MONDAY)) wk,
  COUNT(*) purchases, COUNTIF(ecommerce.purchase_revenue IS NULL) null_rev,
  ROUND(COUNTIF(ecommerce.purchase_revenue IS NULL)/COUNT(*)*100,1) null_rev_pct,
  ROUND(SUM(IFNULL(ecommerce.purchase_revenue,0)),0) revenue
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` WHERE event_name='purchase'
GROUP BY 1 ORDER BY 1;
