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
| `current_month_kpi_mart` | current month | 1 | 상단 scorecard 및 MoM 비교 |
| `monthly_funnel_mart` | month | 3 | CVR 하락 단계 진단 |

데이터 기간:
- 2020-11-01 to 2021-01-31
- GA4 이커머스 이벤트 단위 샘플 데이터

## 지표 정의 메모

`orders`는 purchase event count가 아니라 **구매가 발생한 distinct session count**로 정의한다.

이유:
- 이 프로젝트에서는 운영 KPI 해석을 단순화하기 위해 한 세션의 구매를 최대 1건으로 본다.
- 따라서 `orders = purchase_sessions`로 정의한다.
- 이 정의에서는 `Revenue = Sessions x Session CVR x AOV`가 정확히 성립한다.
- transaction ID와 purchase event 중복은 data quality check 항목으로만 관리한다.

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

8. `sql/07_current_month_kpi_mart.sql`
   - 현재 분석 월과 전월을 비교하는 scorecard용 mart 생성

9. `sql/08_monthly_funnel_mart.sql`
   - Loose session funnel 기준 월별 전환 단계 mart 생성
   - Session → Product View → Add to Cart → Checkout → Purchase

## 자동 생성 대시보드

Looker Studio UI 배치와 별도로, 포트폴리오 화면 퀄리티를 빠르게 맞추기 위해 정적 HTML 대시보드를 추가했다.

- 위치: `dashboard/index.html`
- 데이터: `data/daily_kpi_mart.csv`, `data/monthly_kpi_mart.csv`, `data/daily_segment_mart.csv`
- 구성: Executive KPI, Revenue Trend, KPI Decomposition, Conversion Signal, Segment Risk, Diagnosis Note

상단 KPI는 월별 distinct grain 이슈를 피하기 위해 `monthly_kpi_mart` 기준으로 계산하고, 일별 추세 차트는 `daily_kpi_mart`를 사용한다.

대시보드 상단 필터에서 Month, Channel, Device, User Type을 선택할 수 있다. 세그먼트 리스트의 행을 클릭하면 해당 segment 기준으로 KPI와 차트가 다시 계산된다.

주의:
- 전체 월별 KPI는 exact monthly mart 기준이다.
- Channel/Device/User Type drill-down은 `daily_segment_mart`의 daily grain을 선택 기간 안에서 합산한 방향성 분석용이다.
- 1월 Revenue 하락은 원천 BigQuery 월별 exact 집계에서도 확인된다.
- purchase event와 transaction ID에는 중복이 있으므로, 이 프로젝트의 `orders`는 purchase event count가 아니라 purchase session count로 정의한다.

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
