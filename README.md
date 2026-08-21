# GA4 이커머스 운영 BI

프로젝트 방향:

> GA4 Merchandise Store 이벤트 데이터를 BigQuery SQL로 가공해 운영 KPI mart를 만들고, Looker Studio에서 이커머스 KPI를 모니터링하며 CVR 하락 이슈를 퍼널/세그먼트 단위로 진단한다.

## 데이터 소스

BigQuery public dataset:

```sql
`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
```

프로젝트 관리용 dataset:

```sql
`bigquery-457902.ga4_ops_bi`
```

관리 중인 mart 테이블:

| Table | Grain | Rows | Purpose |
|---|---|---:|---|
| `daily_kpi_mart` | date | 92 | 핵심 KPI 모니터링 |
| `daily_funnel_mart` | date x device x source/medium/channel | 2,351 | 퍼널 진단 |
| `daily_segment_mart` | date x device x source/medium/channel x user type | 4,320 | 세그먼트 drill-down |
| `monthly_kpi_mart` | month | 3 | 월별 KPI 비교 |

데이터 기간:
- 2020-11-01 to 2021-01-31
- GA4 이커머스 이벤트 단위 샘플 데이터

## 지표 정의 메모

`orders`는 distinct transaction ID가 아니라 purchase event count로 정의한다.

이유:
- 샘플 데이터에 중복 transaction ID가 있다.
- 일부 transaction ID는 `(not set)` 같은 placeholder 값이다.
- transaction ID 품질은 핵심 주문 지표가 아니라 data quality check 항목으로 관리한다.

## Grain 결정

핵심 mart는 **daily grain**으로 만든다.

이유:
- 운영 BI는 일 단위 모니터링이 자연스럽다.
- daily row를 Looker Studio에서 week/month로 집계할 수 있다.
- 일별 추세를 보면 spike/drop과 요일 패턴을 확인하기 쉽다.
- 데이터가 3개월뿐이므로 월간 장기 추세가 아니라 월별 KPI 이슈 진단으로 활용하는 것이 적절하다.

## SQL 파일

실행 순서:

1. `sql/00_data_profile.sql`
   - 데이터 기간, 이벤트 구성, 월별 KPI, 일별 completeness 확인

2. `sql/01_daily_kpi_mart.sql`
   - date당 1 row
   - Executive Monitoring 화면에 사용

3. `sql/02_daily_funnel_mart.sql`
   - date, device, channel/source/medium 단위
   - Funnel Diagnosis 화면에 사용

4. `sql/03_daily_segment_mart.sql`
   - date, device, channel/source/medium, user type 단위
   - Segment Drill-down 화면에 사용

5. `sql/04_dq_checks.sql`
   - identifier, purchase transaction ID, 중복 transaction, revenue reconciliation, session grain 검증

6. `sql/build_tables.sql`
   - `bigquery-457902.ga4_ops_bi` 안의 관리용 mart 테이블을 생성/갱신

7. `sql/06_monthly_kpi_mart.sql`
   - Looker Studio 월별 KPI 비교용 mart 생성

## Looker Studio 대시보드 구성

추천 페이지:

1. Executive Monitoring
2. Funnel Diagnosis
3. Segment Drill-down & Action

핵심 스토리:

Revenue = Sessions x CVR x AOV

Revenue가 하락했을 때 Sessions, CVR, AOV 중 어떤 요소가 영향을 주었는지 먼저 분해한다. CVR 하락이 확인되면 아래 축으로 원인을 좁힌다.

- Funnel step
- Device
- Channel/source/medium
- New vs Returning user
- 필요 시 item/category
