-- Definition checks: which timezone is event_date in, and is revenue all USD?
WITH e AS (
  SELECT event_date, event_timestamp, event_name,
    ecommerce.purchase_revenue AS rev, ecommerce.purchase_revenue_in_usd AS rev_usd,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'currency') AS currency
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
)
SELECT 'events' AS k, COUNT(*) AS n FROM e
UNION ALL SELECT 'event_date_ne_utc_date', COUNTIF(PARSE_DATE('%Y%m%d', event_date) != DATE(TIMESTAMP_MICROS(event_timestamp))) FROM e
UNION ALL SELECT 'event_date_ne_la_date', COUNTIF(PARSE_DATE('%Y%m%d', event_date) != DATE(TIMESTAMP_MICROS(event_timestamp), 'America/Los_Angeles')) FROM e
UNION ALL SELECT 'purchases', COUNTIF(event_name = 'purchase') FROM e
UNION ALL SELECT CONCAT('purchase_currency=', IFNULL(currency, 'null')), COUNT(*) FROM e WHERE event_name = 'purchase' GROUP BY currency
UNION ALL SELECT 'purchase_rev_ne_rev_usd', COUNTIF(rev IS NOT NULL AND ABS(rev - IFNULL(rev_usd, -1)) > 0.01) FROM e WHERE event_name = 'purchase';
