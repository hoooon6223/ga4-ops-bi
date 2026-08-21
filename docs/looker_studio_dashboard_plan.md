# Looker Studio 대시보드 구현안

## 방향

이번 대시보드는 분석을 많이 보여주는 화면이 아니라, 운영자가 핵심 KPI 이상을 빠르게 읽는 화면으로 만든다.

핵심 질문:

> 2021년 1월 Revenue 하락은 Sessions, CVR, AOV 중 무엇과 함께 발생했는가?

## 데이터 소스

Looker Studio에서 BigQuery connector로 아래 테이블 2개를 연결한다.

```text
bigquery-457902.ga4_ops_bi.daily_kpi_mart
bigquery-457902.ga4_ops_bi.monthly_kpi_mart
```

사용 기준:

| Data Source | 용도 |
|---|---|
| `daily_kpi_mart` | 일별 trend, 7일 이동평균, daily monitoring |
| `monthly_kpi_mart` | 월별 KPI scorecard, 2020-12 vs 2021-01 비교 |

## 페이지 구성

우선 1페이지로 시작한다.

페이지 이름:

```text
Executive KPI Monitoring
```

추천 크기:

```text
16:9 Landscape
```

## 레이아웃

```text
┌─────────────────────────────────────────────────────────────┐
│ Title + Date Range Filter                                   │
├─────────────┬─────────────┬─────────────┬─────────────┬─────┤
│ Revenue     │ Sessions    │ CVR         │ AOV         │ RPS │
├─────────────────────────────┬───────────────────────────────┤
│ Daily Revenue Trend          │ Daily CVR Trend                │
├─────────────────────────────┴───────────────────────────────┤
│ Monthly KPI Comparison Table                                  │
├─────────────────────────────────────────────────────────────┤
│ Diagnosis Summary                                             │
└─────────────────────────────────────────────────────────────┘
```

## 차트 구성

### 1. Header

Title:

```text
E-commerce Operations KPI Monitoring
```

Subtitle:

```text
GA4 Merchandise Store | BigQuery KPI Mart | 2020-11-01 ~ 2021-01-31
```

Filter:
- Date range control
- 기본 기간: 2020-11-01 ~ 2021-01-31

### 2. KPI Scorecards

Data source:

```text
monthly_kpi_mart
```

기본 비교는 2021-01 vs 2020-12로 둔다.

Scorecard:
- Revenue
- Sessions
- Session CVR
- AOV
- Revenue per Session

표기:
- Revenue: currency 또는 number
- Sessions: number
- Session CVR: percent
- AOV: number
- Revenue per Session: number

### 3. Daily Revenue Trend

Data source:

```text
daily_kpi_mart
```

Chart:
- Time series

Dimension:
- `date`

Metric:
- `revenue`

Style:
- Line color: dark blue or charcoal
- Optional: show points off
- Gridlines light gray

### 4. Daily CVR Trend

Data source:

```text
daily_kpi_mart
```

Chart:
- Time series

Dimension:
- `date`

Metric:
- `session_cvr`

Style:
- Percent format
- Line color: muted red or orange
- 2021년 1월 하락이 보이도록 축을 과하게 압축하지 않는다.

### 5. Monthly KPI Comparison Table

Data source:

```text
monthly_kpi_mart
```

Dimension:
- `month`

Metrics:
- `revenue`
- `sessions`
- `session_cvr`
- `aov`
- `revenue_per_session`

정렬:
- `month` ascending

목적:
- 2020-12 대비 2021-01의 Revenue, CVR, AOV 하락을 한눈에 보여준다.

### 6. Diagnosis Summary

텍스트 박스로 넣는다.

추천 문구:

```text
2021년 1월 Revenue는 2020년 12월 대비 크게 하락했다.
Sessions 감소도 있었지만, Session CVR은 1.59%에서 0.94%로 하락했고 AOV도 65.96에서 47.63으로 감소했다.
따라서 다음 분석은 CVR 하락의 funnel step과 segment 집중 여부를 확인하는 방향으로 확장한다.
```

## 디자인 원칙

- 배경은 흰색 또는 매우 옅은 회색.
- 카드 배경은 흰색, border는 연한 회색.
- 색상은 2~3개만 사용한다.
- 빨간색은 하락/주의 신호에만 사용한다.
- 차트 수는 4~6개 이내로 제한한다.
- 첫 페이지에서는 channel/device/funnel까지 넣지 않는다.
- KPI 카드와 trend가 먼저 보여야 한다.

## 다음 확장

첫 페이지에서 CVR 하락을 확인한 뒤, 필요할 때만 추가 페이지를 만든다.

후보:
- Funnel Diagnosis
- Channel / Device Drill-down
- New vs Returning User Analysis

