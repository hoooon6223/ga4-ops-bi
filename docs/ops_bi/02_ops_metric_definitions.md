# 운영 BI 지표 정의집 (Ops Metric Definitions)

- 버전: v1.1 (2026-11-05)
- 근거: `docs/ops_bi/01_eda_kpi_candidates.md`, `sql/eda/08~09_*.sql`
- 원본: `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`

---

## 0. 운영 원칙

1. **이 문서가 유일한 기준이다.** 대시보드, CSV, AI 코멘트의 모든 숫자는 이 문서의 `metric_id` 정의로만 계산한다.
2. **SQL은 metric_id를 주석으로 남긴다.** 예: `-- metric: K01_revenue`. 문서와 SQL이 1:1로 추적되어야 한다.
3. **정의를 바꾸면 버전을 올리고 변경 이력(8장)에 남긴다.** 과거 리포트와 숫자가 달라지는 이유를 설명할 수 있어야 한다.
4. **집계 전에 대사(6장)를 먼저 통과해야 한다.** 대사가 실패한 날은 숫자를 내보내되 "해석 보류"로 표시한다.
5. 기존 분석 프로젝트의 `docs/metric_definitions.md`와 `core_f_orders`는 수정하지 않는다. 운영 BI는 이 문서와 `ops_*` 테이블을 쓴다.

---

## 1. 기본 단위와 키

| 단위 | 키 | 정의 |
|---|---|---|
| 사용자 | `user_pseudo_id` | GA4 익명 ID. 실제 회원 ID가 아니다. |
| 세션 | `session_id = user_pseudo_id + '-' + ga_session_id` | ga_session_id 누락 0건 (EDA 확인) |
| 주문 | `order_key` | 아래 1-1 규칙 |
| 날짜 | `event_date` (UTC 기준 GA4 export 날짜) | 일 단위 집계 기준 |
| 주 | 월요일 시작 (`WEEK(MONDAY)`) | 기존 분석 프로젝트와 동일 |

### 1-1. 주문 키 규칙 (중복 제거)

GA4는 주문이 아니라 이벤트를 기록한다. 결제 완료 페이지를 새로고침하면 같은 주문의 purchase 이벤트가 다시 기록된다. 그래서 주문은 아래 키로 묶고 **가장 먼저 기록된 이벤트 1건만** 남긴다.

```text
order_key =
  transaction_id가 있으면       → 'T:' + transaction_id
  없거나 '(not set)'이면        → 'S:' + session_id + '|' + purchase_revenue
```

**근거 (검증 쿼리: `sql/eda/08_session_dedupe_validation.sql`)**

| 확인 | 결과 | 판단 |
|---|---|---|
| 중복 transaction_id 중 같은 세션 안에서 발생 | 326개 중 311개 (95%) | 중복은 세션 안 새로고침 패턴 → 세션이 거래번호 없는 건의 대체 키로 적합 |
| 한 세션에 서로 다른 transaction_id가 2개 이상 | 236개 세션 | "세션당 주문 1건"으로 세면 실제 주문을 놓침 → 세션 + 금액으로 구분 |
| 거래번호 없는 구매가 있는 세션 | 813개 | 이 중 같은 세션 안에 2건 이상은 38개뿐 |

**알려진 한계**
- 거래번호 없는 주문이 같은 세션에서 같은 금액으로 2번 실제 결제되면 1건으로 합쳐진다. (드문 경우로 판단)
- 같은 거래번호가 서로 다른 세션에 걸친 15건은 첫 세션에만 주문이 남는다. (6장 대사 R3에서 차이로 설명)

---

## 2. 기준 테이블 (sql/pipeline/01~05에서 생성)

| 테이블 | Grain | 내용 |
|---|---|---|
| `ops_f_orders` | 주문 (`order_key`) | 1-1 규칙으로 중복 제거한 주문. `has_revenue` 플래그 포함 |
| `ops_f_sessions` | 세션 (`session_id`) | 퍼널 도달 플래그 + 해당 세션의 주문 수·매출 (`ops_f_orders`를 세션으로 합산) |
| `ops_kpi_daily` | 날짜 | Tier 1·2 지표 일별 값 |
| `ops_kpi_comparison` | 날짜 × 지표 | DoD / WoW / MoM 증감과 flag |
| `ops_dq_results` | 날짜 × 체크 | Tier 3 품질 체크와 대사 결과 |

---

## 3. Tier 1 헤드라인 KPI (확정)

| metric_id | 지표 | 계산식 | Grain | 기준 테이블 | 비교·flag 기준 | 주의사항 |
|---|---|---|---|---|---|---|
| K01_revenue | 매출 | `SUM(purchase_revenue)` | 주문 | ops_f_orders | rolling 7d WoW, ±25% 초과 시 notable | 매출 누락 주문은 0으로 합산. 누락률이 높은 날은 DQ03이 해석 보류 |
| K02_orders | 주문 수 | `COUNT(DISTINCT order_key)` | 주문 | ops_f_orders | rolling 7d WoW, ±25% | 매출 누락과 무관하게 거래 규모를 보여줌 |
| K03_sessions | 세션 | `COUNT(DISTINCT session_id)` | 세션 | ops_f_sessions | 일 단위 WoW(같은 요일), ±20% | 주말이 평일보다 약 30% 낮음. DoD로 판단하지 않음 |
| K04_active_users | 활성 사용자 | `COUNT(DISTINCT user_pseudo_id)` | 사용자 | ops_f_sessions | 일 단위 WoW, ±20% | 일 단위는 DAU, 주 단위는 WAU |
| K05_session_cvr | 세션 전환율 | 주문이 1건 이상인 세션 / 전체 세션 | 세션 | ops_f_sessions | rolling 7d WoW, ±0.2%p | **중복 제거된 주문 기준**. 원본 purchase 이벤트 기준과 약간 다름 (R3) |
| K06_aov | 객단가 | `K01 / 매출이 있는 주문 수` | 주문 | ops_f_orders | rolling 7d WoW, ±15% | 매출 누락 주문은 분모에서 제외해야 객단가가 왜곡되지 않음 |

**매출 분해 관계 (일 단위 설명용)**

```text
매출 ≈ 세션 × 세션 전환율 × (주문 수 / 주문 세션 수) × 객단가
```

한 세션에 주문이 여러 건인 경우가 있어 "주문 세션당 주문 수" 항이 들어간다. 대부분 1에 가까우므로 리포트에서는 `세션 × 전환율 × 객단가`로 설명하고, 이 항은 참고값으로 둔다.

flag 임계치는 EDA의 92일 변동성 분포에서 잡은 v1.0 초안이다 (01 문서 2-3장).

---

## 4. Tier 2 진단 지표

| metric_id | 지표 | 계산식 | Grain | 용도 |
|---|---|---|---|---|
| D01_view_item_rate | 상품 조회율 | view_item 세션 / 세션 | 세션 | 퍼널 입구 |
| D02_add_to_cart_rate | 장바구니율 | add_to_cart 세션 / view_item 세션 | 세션 | 최대 이탈 구간 |
| D03_checkout_rate | 체크아웃 진입률 | begin_checkout 세션 / add_to_cart 세션 | 세션 | |
| D04_purchase_completion_rate | 결제 완료율 | 주문 세션 / begin_checkout 세션 | 세션 | |
| D05_new_user_share | 신규 사용자 비중 | first_visit 사용자 / 활성 사용자 | 사용자 | 유입 질 변화 |
| D06_arppu | ARPPU | K01 / 구매 사용자 수 | 사용자 | 주간 분해 (WAU × Buyer CVR × ARPPU) |
| D07_by_dimension | 차원별 K01·K02·K05 | 기기 / 국가 상위 5 + 기타 / 유입 매체 | 세션 | 변화 위치 특정 |

퍼널 지표는 모두 **세션 단위 도달 여부**(이벤트 횟수 아님)로 센다. 비율은 %p 차이로 비교한다.

---

## 5. Tier 3 데이터 품질 체크

| check_id | 체크 | 기준 | 등급 | EDA 평상시 값 |
|---|---|---|---|---|
| DQ01_arrival | 데이터 도착 | 당일 이벤트 > 0 | FAIL | 92일 모두 도착 |
| DQ02_session_spike | 세션 급변 | 같은 요일 대비 ±40% 초과 | WARN | WoW 상위 10%가 33% |
| DQ03_null_revenue | 매출 누락률 | 구매 중 매출 null > 10% WARN, > 30% FAIL | WARN/FAIL | 평상시 2~4%, 1/25 주 70% |
| DQ04_dup_orders | 주문 중복률 | (purchase 이벤트 − 주문) / purchase 이벤트 > 15% | WARN | 전체 7.2% |
| DQ05_missing_tid | 거래번호 누락률 | > 20% | WARN | 15.9% |
| DQ06_item_reconcile | 주문 매출 vs 상품 매출 | 차이 1% 초과 주문 비중 > 20% | WARN | 13.8% |
| DQ07_order_revenue_gap | 주문-매출 괴리 | 주문 WoW ±20% 이내인데 매출 WoW ≤ −50% | FAIL (해석 보류) | 1/25 주 사례 |
| DQ08_funnel_tracking | 퍼널 순서 정합성 | 장바구니 세션 < 체크아웃 세션이면 수집 누락 의심 | WARN (D02·D03 해석 보류) | 11/01~11/24 중 23일 해당. 장바구니 이벤트가 거의 0건 |

---

## 6. 집계 대사 규칙 (집계 전에 매일 실행)

같은 숫자를 서로 다른 단위로 계산해서 맞아떨어지는지 확인한다. 하나라도 실패하면 그날 리포트에 "해석 보류"를 붙인다.

| rule_id | 대사 | 통과 조건 | 92일 검증 결과 (`09_order_reconciliation.sql`) |
|---|---|---|---|
| R1 | 이벤트 → 주문 | 주문 수 ≤ purchase 이벤트 수 | 5,283 ≤ 5,692 ✓ |
| R2 | 주문 매출 = 세션 합산 매출 | 차이 0 | 338,153 = 338,153 ✓ |
| R3 | 주문 세션 수 vs 원본 purchase 세션 수 | 차이가 "세션을 넘는 중복 거래번호" 수 이하 | 4,837 vs 4,848, 차이 11 ≤ 15 ✓ |
| R4 | 주문 수 = 거래번호 있는 주문 + 없는 주문 | 차이 0 | 4,451 + 832 = 5,283 ✓ |
| R5 | 중복 제거 매출 ≤ 원본 매출 | 항상 성립 | 338,153 ≤ 362,165 ✓ (−6.6%) |
| R6 | 일별 합계 = 기간 합계 | 일별 K01·K02 합이 기간 집계와 일치 | 파이프라인 구축 시 추가 |

---

## 7. 비교 기준

| 비교 | 정의 | 사용 |
|---|---|---|
| DoD | 어제 vs 그저께 | 표시만 함. flag에 사용하지 않음 |
| WoW | 어제 vs 지난주 같은 요일 / rolling 7d vs 직전 7d | **flag 판단 기본값** |
| MoM | 이번 달 1일~어제 누적 vs 지난달 같은 일수 누적 | 2020-12-01부터 계산 |

---

## 8. 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0 | 2026-11-05 | 최초 작성. Tier 1 확정, 주문 키 규칙(거래번호 → 세션 + 금액) 확정, 대사 규칙 R1~R5 검증 |
| v1.1 | 2026-11-05 | DQ08 퍼널 순서 정합성 추가 (11월 초 add_to_cart 수집 누락 발견). Tier 2 flag 임계치 초안 추가 (D01·D02 ±2%p, D03·D04·D05 ±5%p, rolling 7d 기준). 세션 grain을 "세션 × 날짜"로 명시 (자정을 넘는 세션은 각 날짜에 1번씩 집계) |
