# GA4 운영 BI 대시보드 Grain 설계

## 추천 Grain

핵심 mart는 **daily grain**으로 만든다.

이유:
- 운영 대시보드는 일 단위 모니터링을 지원해야 한다.
- daily mart는 Tableau에서 week/month 단위로 쉽게 집계할 수 있다.
- 일별 추세를 보면 KPI 하락, spike, 요일 효과를 확인하기 좋다.
- 데이터 기간이 2020-11-01부터 2021-01-31까지 3개월이므로, 월별 비교는 장기 추세 분석이 아니라 단기 이슈 진단으로 해석해야 한다.

## 대시보드 비교 기준

기본 모니터링:
- 일별 KPI trend
- 7일 이동평균
- 전주 대비 변화

포트폴리오 진단 케이스:
- 전월 대비 CVR 하락 진단
- 월별 비교가 애매하면 이전 4주 vs 최근 4주 비교로 전환

## 핵심 KPI 분해

Revenue = Sessions x CVR x AOV

정의:
- Sessions: distinct `user_pseudo_id + ga_session_id`
- Purchasers: `purchase`가 발생한 distinct user
- Orders: purchase event count
- Revenue: `ecommerce.purchase_revenue`
- CVR: purchase sessions / sessions
- AOV: revenue / orders
- Revenue per Session: revenue / sessions

메모:
- 이 GA4 샘플에는 중복 transaction ID와 `(not set)` 같은 placeholder ID가 있다.
- 대시보드 안정성을 위해 orders는 purchase event count로 정의하고, transaction ID 품질은 DQ check에서 별도로 다룬다.

## Tableau 페이지

1. Executive Monitoring
   - Revenue, Sessions, CVR, AOV, Orders, Purchasers
   - 일별 trend와 MoM/WoW 비교
   - Revenue decomposition

2. Funnel Diagnosis
   - Session -> View Item -> Add to Cart -> Begin Checkout -> Purchase
   - 단계별 전환율과 drop-off
   - 현재 기간 vs 비교 기간

3. Segment Drill-down
   - Device, channel, source/medium, user type, item category
   - CVR 변화 heatmap
   - 문제 세그먼트 Top table
