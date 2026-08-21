# GA4 E-commerce Operations BI

Portfolio direction:

> Build BigQuery SQL marts from GA4 Merchandise Store event data, then use Tableau to monitor ecommerce KPIs and diagnose a CVR drop through funnel and segment drill-downs.

## Source

BigQuery public dataset:

```sql
`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
```

Managed project dataset:

```sql
`bigquery-457902.ga4_ops_bi`
```

Managed mart tables:

| Table | Grain | Rows | Purpose |
|---|---|---:|---|
| `daily_kpi_mart` | date | 92 | Executive KPI monitoring |
| `daily_funnel_mart` | date x device x source/medium/channel | 2,351 | Funnel diagnosis |
| `daily_segment_mart` | date x device x source/medium/channel x user type | 4,320 | Segment drill-down |

Official coverage:
- 2020-11-01 to 2021-01-31
- Event-level GA4 ecommerce sample data

## Metric Note

`orders` are defined as purchase event count, not distinct transaction ID.

Reason:
- The sample data contains duplicated transaction IDs.
- Some transaction IDs are placeholders such as `(not set)`.
- Transaction ID quality is handled as a data quality check instead of the primary order metric.

## Current Grain Decision

Core marts use **daily grain**.

Why:
- Daily is the natural grain for operations monitoring.
- Tableau can aggregate daily rows to week/month.
- Daily trends make spikes and drops visible.
- With only 3 months of data, monthly comparison should be used as a CVR issue case, not a long-term trend claim.

## SQL Files

Run in this order:

1. `sql/00_data_profile.sql`
   - Check date coverage, event mix, monthly KPI sanity, daily completeness.

2. `sql/01_daily_kpi_mart.sql`
   - One row per date.
   - Used for Executive Monitoring.

3. `sql/02_daily_funnel_mart.sql`
   - One row per date, device, channel/source/medium.
   - Used for Funnel Diagnosis.

4. `sql/03_daily_segment_mart.sql`
   - One row per date, device, channel/source/medium, user type.
   - Used for Segment Drill-down.

5. `sql/04_dq_checks.sql`
   - Validate identifiers, purchase transaction IDs, duplicate transactions, revenue reconciliation, and session grain.

6. `sql/build_tables.sql`
   - Creates or replaces the managed BigQuery mart tables in `bigquery-457902.ga4_ops_bi`.

## Tableau Build

Recommended pages:

1. Executive Monitoring
2. Funnel Diagnosis
3. Segment Drill-down & Action

Core story:

Revenue = Sessions x CVR x AOV

If revenue drops and sessions/AOV are stable, diagnose the CVR drop by:
- Funnel step
- Device
- Channel/source/medium
- New vs returning user
- Item/category if needed in a later mart
