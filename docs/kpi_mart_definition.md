# daily_kpi_mart 정의

## 목적

`daily_kpi_mart`는 Looker Studio Executive Monitoring 대시보드의 기본 테이블이다.

이 테이블의 목적은 다음 질문에 답하는 것이다.

- 일별 Revenue, Sessions, CVR, AOV가 어떻게 변했는가?
- 2021년 1월 Revenue 하락은 Sessions, CVR, AOV 중 무엇과 함께 움직였는가?
- 운영팀이 먼저 확인해야 할 KPI 이상 신호가 있는가?

## Grain

```text
date
```

즉 하루에 1 row가 생성된다.

데이터 기간:

```text
2020-11-01 ~ 2021-01-31
```

총 92 rows.

## Source

```sql
`bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
```

## Session 정의

GA4 event parameter의 `ga_session_id`와 `user_pseudo_id`를 결합해 session_id를 만든다.

```sql
CONCAT(
  user_pseudo_id,
  '-',
  CAST((SELECT value.int_value FROM UNNEST(event_params) WHERE key = 'ga_session_id') AS STRING)
) AS session_id
```

## 지표 정의

| Column | 정의 |
|---|---|
| `date` | 이벤트 날짜 |
| `sessions` | 해당 일자의 distinct session_id |
| `users` | 해당 일자의 distinct user_pseudo_id |
| `purchasers` | 해당 일자에 purchase event가 발생한 distinct user_pseudo_id |
| `purchase_sessions` | 해당 일자에 purchase event가 발생한 distinct session_id |
| `orders` | 구매가 발생한 distinct session count |
| `revenue` | purchase event의 `ecommerce.purchase_revenue` 합계 |
| `session_cvr` | purchase_sessions / sessions |
| `user_cvr` | purchasers / users |
| `aov` | revenue / purchase_sessions |
| `revenue_per_session` | revenue / sessions |

## 집계 시 주의점

`orders`와 `revenue`는 현재 정의상 기간 합산이 가능하다. 단, `orders`는 purchase event count가 아니라 purchase session count다.

반면 아래 지표는 distinct count 기반이므로, daily mart를 월/전체 기간으로 단순 합산하면 중복이 생길 수 있다.

- `sessions`
- `users`
- `purchasers`
- `purchase_sessions`

예를 들어 `users`는 일별 distinct user이므로, 월별로 `SUM(users)`를 하면 같은 유저가 여러 날짜에 방문한 경우 중복 집계된다.

월별 distinct users나 purchasers를 엄밀하게 보려면 raw event에서 월 단위로 다시 `COUNT(DISTINCT ...)`해야 한다.

## 대시보드 활용 기준

일별 모니터링:
- `daily_kpi_mart`를 그대로 사용한다.

월별 Revenue, Orders, AOV:
- `SUM(revenue)`, `SUM(orders)`, `SUM(revenue) / SUM(purchase_sessions)` 사용 가능.

월별 Sessions, CVR:
- 빠른 운영 모니터링에서는 daily mart 합산 기반 근사치를 사용할 수 있다.
- 포트폴리오에서 엄밀한 월별 지표를 제시할 때는 raw event 기준 월집계 쿼리를 함께 사용한다.

검증 쿼리:

```text
sql/05_kpi_mart_validation.sql
```
