-- Dimension coverage for slicing KPIs
SELECT 'device' AS dim, device.category AS val, COUNT(DISTINCT user_pseudo_id) users, ROUND(SUM(IF(event_name='purchase',ecommerce.purchase_revenue,0)),0) revenue FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` GROUP BY 1,2
UNION ALL SELECT 'medium', traffic_source.medium, COUNT(DISTINCT user_pseudo_id), ROUND(SUM(IF(event_name='purchase',ecommerce.purchase_revenue,0)),0) FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` GROUP BY 1,2
UNION ALL SELECT 'country_top', geo.country, COUNT(DISTINCT user_pseudo_id), ROUND(SUM(IF(event_name='purchase',ecommerce.purchase_revenue,0)),0) FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*` GROUP BY 1,2
ORDER BY dim, users DESC;
