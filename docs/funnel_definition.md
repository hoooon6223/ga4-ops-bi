# 퍼널 정의

## 목적

본 프로젝트의 핵심 KPI는 Revenue이며, Revenue는 다음 구조로 분해한다.

```text
Revenue = Sessions x Session CVR x AOV
```

따라서 퍼널은 단순 이벤트 나열이 아니라 **Session CVR 하락 원인을 진단하기 위한 구매 전환 퍼널**로 정의한다.

## Funnel Type

이 분석에서는 **Cumulative loose session funnel**을 사용한다.

세션 안에서 해당 이벤트가 한 번이라도 발생하면 그 단계 후보로 본다. 단, 단계별 전환율이 100%를 넘지 않도록 Product View 이후 단계는 이전 단계 이벤트가 모두 존재해야 도달한 것으로 본다. 이벤트 발생 순서까지는 강제하지 않는다.

이유:
- 운영 BI 관점에서는 단계별 병목 위치를 안정적으로 확인하는 것이 목적이다.
- GA4 샘플 데이터는 checkout 이벤트가 add_to_cart 없이 찍히는 등 이벤트 누락 이슈가 있어 단순 loose funnel은 단계 전환율이 100%를 넘을 수 있다.
- strict ordered funnel은 이벤트 순서 문제로 과도하게 낮은 전환율을 만들 수 있다.
- Session CVR을 단계별로 분해하기에 적합하다.

## 단계 정의

```text
Session
→ Product View
→ Add to Cart
→ Checkout
→ Purchase
```

| Step | Definition |
|---|---|
| Session | distinct session_id |
| Product View | session_id where `view_item` occurred |
| Add to Cart | session_id where `view_item` and `add_to_cart` occurred |
| Checkout | session_id where `view_item`, `add_to_cart`, and `begin_checkout` occurred |
| Funnel Purchase | session_id where `view_item`, `add_to_cart`, `begin_checkout`, and `purchase` occurred |
| KPI Purchase | session_id where `purchase` occurred |

## 전환율 정의

```text
Product View Rate = Product View Sessions / Sessions
View to Cart Rate = Add to Cart Sessions / Product View Sessions
Cart to Checkout Rate = Checkout Sessions / Add to Cart Sessions
Checkout to Purchase Rate = Funnel Purchase Sessions / Checkout Sessions
Funnel Completion Rate = Funnel Purchase Sessions / Sessions
Session CVR = KPI Purchase Sessions / Sessions
```

이 구조를 통해 1월 Session CVR 하락이 어떤 단계의 전환율 하락에서 비롯됐는지 확인한다.

`Session CVR`은 전체 구매 세션 기준 KPI로 유지하고, 단계별 퍼널 전환율은 누적 경로 기준으로 해석한다.
