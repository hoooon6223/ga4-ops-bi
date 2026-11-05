-- Event name distribution
SELECT event_name, COUNT(*) AS events, COUNT(DISTINCT user_pseudo_id) AS users,
  ROUND(COUNT(*)/SUM(COUNT(*)) OVER()*100,2) AS pct_events
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
GROUP BY 1 ORDER BY events DESC;
