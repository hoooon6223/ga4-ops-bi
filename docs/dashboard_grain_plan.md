# GA4 Operations BI Dashboard Grain Plan

## Recommended Grain

Use **daily grain** for the core marts.

Reason:
- Operations dashboards should support day-to-day monitoring.
- Daily marts can be aggregated to week/month in Tableau.
- Daily trends make KPI drops, spikes, and weekday effects visible.
- The dataset only covers 2020-11-01 to 2021-01-31, so monthly comparison should be framed as an issue diagnosis, not a long-term trend analysis.

## Dashboard Comparison Logic

Primary monitoring:
- Daily KPI trend
- 7-day moving average
- Week-over-week change

Portfolio case:
- Month-over-month CVR drop diagnosis
- If monthly data looks uneven, switch to previous 4 weeks vs recent 4 weeks.

## Core KPI Decomposition

Revenue = Sessions x CVR x AOV

Definitions:
- Sessions: distinct `user_pseudo_id + ga_session_id`
- Purchasers: distinct users with `purchase`
- Orders: purchase events
- Revenue: `ecommerce.purchase_revenue`
- CVR: purchase sessions / sessions
- AOV: revenue / orders
- Revenue per Session: revenue / sessions

Note:
- This GA4 sample has duplicated and placeholder transaction IDs such as `(not set)`.
- For dashboard stability, orders are defined as purchase event count, while transaction ID quality is treated as a DQ check.

## Tableau Pages

1. Executive Monitoring
   - Revenue, Sessions, CVR, AOV, Orders, Purchasers
   - Daily trend and MoM/WoW comparison
   - Revenue decomposition

2. Funnel Diagnosis
   - Session -> View Item -> Add to Cart -> Begin Checkout -> Purchase
   - Step conversion rates and drop-off
   - Current period vs comparison period

3. Segment Drill-down
   - Device, channel, source/medium, user type, item category
   - CVR change heatmap
   - Problem segment top table
