# 이슈 진단 케이스 요약

## 선정 케이스

대시보드 진단 케이스는 **2021년 1월 CVR 하락**으로 잡는다.

GA4 샘플 데이터 기간:
- 2020-11-01 to 2021-01-31
- 완전한 일별 데이터 92일

## 월별 KPI Profile

| Month | Sessions | Users | Purchasers | Orders | Revenue | Session CVR | AOV |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2020-11 | 108,401 | 79,421 | 1,532 | 2,054 | 144,260 | 1.49% | 70.23 |
| 2020-12 | 133,368 | 104,315 | 1,975 | 2,434 | 160,555 | 1.59% | 65.96 |
| 2021-01 | 118,380 | 94,790 | 1,069 | 1,204 | 57,350 | 0.94% | 47.63 |

## 이 케이스가 적절한 이유

12월에서 1월로 넘어가며:
- Sessions는 감소했지만, 전체 revenue 하락을 단독으로 설명하기에는 부족하다.
- Session CVR은 1.59%에서 0.94%로 크게 하락했다.
- AOV도 65.96에서 47.63으로 하락했다.

대시보드 스토리:

> 2021년 1월 Revenue가 크게 하락했다. KPI decomposition 결과, 단순히 traffic volume만의 문제가 아니라 conversion efficiency가 크게 악화되었고 AOV도 함께 약화되었다. 대시보드는 먼저 CVR 하락을 식별하고, 이후 어떤 funnel step과 segment에서 하락이 집중되었는지 진단해야 한다.

## 대시보드 진단 흐름

1. Executive Monitoring
   - 1월 revenue 및 CVR 하락 감지

2. KPI Decomposition
   - Sessions, CVR, AOV 비교

3. Funnel Diagnosis
   - 하락이 View Item, Add to Cart, Checkout, Purchase 중 어느 단계에 집중되었는지 확인

4. Segment Drill-down
   - Device, Channel, Source/Medium, New/Returning user별로 확인

5. Action
   - 가장 강한 funnel/segment 발견점을 운영 점검 항목으로 전환
