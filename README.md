# GA4 Merch Shop 운영 BI 자동화

매일 같은 지표 정의로 KPI를 집계하고, 데이터 품질을 검사하고, AI 코멘트가 붙은 Power BI 스타일 대시보드를 자동으로 게시하는 파이프라인입니다.

데이터는 BigQuery 공개 데이터셋 `ga4_obfuscated_sample_ecommerce` (2020-11-01 ~ 2021-01-31)입니다. 고정된 과거 데이터라서, **하루치씩 순서대로 흘려 넣는 리플레이 방식**으로 실제 일일 운영을 재현합니다.

## 흐름

```text
GitHub Actions (예약 실행)
  ① 다음 날짜 찾기          마지막으로 적재된 날 + 1
  ② BigQuery 집계           sql/pipeline/01~05 (지표 정의집과 1:1)
       01 주문 중복 제거  →  02 세션 테이블  →  03 일별 KPI  →  04 전일·전주·전월 비교  →  05 품질 체크·대사
  ③ CSV 내보내기            outputs/runs/<날짜>/
  ④ Claude 코멘트           현상만 기록. 숫자는 자리표시로만 인용, 원인·추측 표현 금지 → 검증 → 실패 시 재시도 1회
  ⑤ 대시보드 생성           고정 템플릿에 숫자와 코멘트 채우기 → site/days/<날짜>.html
  ⑥ PDF 보존               같은 대시보드를 PDF로 저장 → site/pdf/<날짜>.pdf, 목록은 site/reports.html
  ⑦ 게시                   저장소에 커밋(영구 보존) + GitHub Pages
```

## 숫자를 믿을 수 있게 만든 장치

| 장치 | 내용 |
|---|---|
| 지표 정의집 | [`docs/ops_bi/02_ops_metric_definitions.md`](docs/ops_bi/02_ops_metric_definitions.md)가 유일한 기준. SQL은 metric_id로 추적 |
| 주문 중복 제거 | GA4는 이벤트 단위라 새로고침 시 구매가 다시 찍힘. 거래번호 → 세션+금액 키로 묶어서 제거 (원본 대비 매출 −6.6%) |
| 품질 체크 DQ01~08 | 데이터 도착, 세션 급변, 매출 누락, 주문 중복, 거래번호 누락, 상품 매출 대사, 주문-매출 괴리, 퍼널 순서 |
| 집계 대사 R1~R5 | 같은 숫자를 이벤트·주문·세션 단위로 따로 계산해서 일치하는지 매일 확인 |
| AI는 숫자를 쓰지 않음 | Claude는 `{{K01_revenue.r7_change}}` 같은 자리표시만 쓰고, 값은 SQL 결과에서 채움. 맨 숫자나 없는 자리표시가 있으면 거절 |
| AI는 해석하지 않음 | 코멘트는 현상(무엇이, 무엇과 비교해, 얼마나)만 기록. "요인·영향·때문·가능성·~일 수 있어요" 같은 원인·추측 표현이 있으면 거절 |
| 멱등성 | 같은 날짜를 다시 돌려도 결과가 같음 (해당 날짜 파티션을 지우고 다시 적재) |

EDA에서 실제로 찾은 데이터 문제는 [`docs/ops_bi/01_eda_kpi_candidates.md`](docs/ops_bi/01_eda_kpi_candidates.md)에 있습니다. 1월 말 매출 누락(구매의 70%가 매출값 없음), 11월 초 장바구니 이벤트 미수집, 주문 이중 수집이 대표적입니다.

## 폴더

```text
sql/pipeline/     매일 도는 집계 SQL (01~05)
sql/eda/          지표 정의 근거가 된 탐색 쿼리
pipeline/         run_daily.py(실행) · ai_summary.py(코멘트+검증) · render_dashboard.py(템플릿) · fmt.py(숫자 표기) · bq.py
templates/        대시보드 템플릿 (개요 / 퍼널·지표 상세 / 데이터 품질)
outputs/runs/     날짜별 CSV와 AI 코멘트 (실행 기록)
site/             게시되는 대시보드
docs/             EDA, 지표 정의집, 설정 가이드
```

## 로컬 실행

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
gcloud auth login                      # bq CLI 인증
export ANTHROPIC_AUTH_TOKEN=...        # Console API 키 (Bearer 방식). 없으면 --skip-ai
.venv/bin/python -m pipeline.run_daily              # 다음 날짜
.venv/bin/python -m pipeline.run_daily --date 2020-12-14
.venv/bin/python -m unittest discover -s tests -t .
```

자동 실행 설정은 [`docs/setup_github_actions.md`](docs/setup_github_actions.md)를 보세요.

## 확장한다면

각 SQL 단계가 독립된 작업이라 Airflow DAG의 task로 그대로 옮길 수 있습니다. 지금 규모(하루 1회, 5단계)에서는 GitHub Actions로 충분하다고 판단했습니다.
