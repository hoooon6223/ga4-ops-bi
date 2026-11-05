# GitHub Actions 자동 실행 설정

키 2개를 GitHub Secrets에 등록하고, Pages를 켜면 끝나요. 키는 코드나 채팅에 붙여 넣지 말고 **GitHub Secrets에만** 넣으세요.

## 1. GCP 서비스 계정 키 → `GCP_SA_KEY`

GitHub 서버가 BigQuery에 접속할 때 쓰는 "로봇 계정"이에요.

1. [Google Cloud 콘솔](https://console.cloud.google.com/) → 프로젝트 `bigquery-457902` 선택
2. **IAM 및 관리자 → 서비스 계정 → 서비스 계정 만들기**
   - 이름: `ga4-ops-bi-runner`
   - 역할 2개 부여:
     - `BigQuery 작업 사용자` (BigQuery Job User): 쿼리 실행
     - `BigQuery 데이터 편집자` (BigQuery Data Editor): `ops_*` 테이블 쓰기
3. 만든 계정 클릭 → **키 → 키 추가 → 새 키 만들기 → JSON** → 파일이 다운로드돼요.
4. GitHub 저장소 → **Settings → Secrets and variables → Actions → New repository secret**
   - Name: `GCP_SA_KEY`
   - Secret: 다운로드한 JSON 파일 내용 전체
5. 등록 후 JSON 파일은 컴퓨터에서 지우세요. 이 폴더 안에 두지 마세요.

> 더 안전한 방법: 키 파일 없이 Workload Identity Federation으로 연결할 수도 있어요. 설정이 길어서 1차 버전은 키 방식으로 했어요.

## 2. Claude API 키 → `ANTHROPIC_API_KEY`

1. [Claude Console](https://platform.claude.com/) → 로그인 → 결제 수단 등록 (사용한 만큼 과금)
2. **Settings → API keys → Create Key**. 지금 발급되는 키는 `sk-ant-usr-`로 시작하고, `Authorization: Bearer` 헤더로 보내야 해요 (예전 `x-api-key` 헤더로 보내면 401).
3. 아래 명령으로 키를 검사하고, 정상(`check: 200`)일 때만 GitHub Secrets `ANTHROPIC_API_KEY`에 등록해요. 워크플로는 이 값을 `ANTHROPIC_AUTH_TOKEN`으로 넘겨서 SDK가 Bearer 방식으로 보내게 해요.

```bash
printf 'Claude API key: '; read -rs K; echo; code=$(curl -s -o /dev/null -w "%{http_code}" https://api.anthropic.com/v1/models -H "Authorization: Bearer $K" -H "anthropic-version: 2023-06-01"); echo "check: $code"; [ "$code" = 200 ] && printf %s "$K" | gh secret set ANTHROPIC_API_KEY -R hoooon6223/ga4-ops-bi; unset K
```

> 공식 문서는 자동 실행(CI)에는 개인 키보다 **서비스 계정 키**를 권장해요. 개인 키는 내 계정으로 동작하기 때문이에요. 이 프로젝트는 개인 포트폴리오라 개인 키로 시작했어요.

하루 1회 짧은 요약이라 비용은 적어요. Console에서 월 사용 한도를 걸어두면 안심이에요.

## 3. GitHub Pages 켜기

저장소 → **Settings → Pages → Build and deployment → Source: GitHub Actions**

무료 계정에서 Pages를 쓰려면 저장소가 **공개(public)** 여야 해요.

## 4. 첫 실행

저장소 → **Actions → ops-bi-daily → Run workflow**

- 성공하면 `https://<GitHub 아이디>.github.io/ga4-ops-bi/`에 대시보드가 게시돼요.
- 이후에는 매시간 하루치씩 자동으로 진행돼요 (`.github/workflows/ops_bi_daily.yml`의 cron).
- 2021-01-31까지 다 돌면 "Replay finished"를 출력하고 아무것도 하지 않아요. 그때 Actions에서 워크플로를 비활성화하세요.

## 실패할 때

| 증상 | 원인 |
|---|---|
| `auth` 단계 실패 | `GCP_SA_KEY` 값이 JSON 전체가 아님 |
| `Access Denied` / `permission` | 서비스 계정 역할 2개 중 하나가 빠짐 |
| 대시보드에 "AI 요약 실패" | `ANTHROPIC_API_KEY` 누락, 결제 미등록, 또는 한도 초과. 숫자 부분은 정상 게시돼요 |
| `deploy` 실패 | Pages Source가 GitHub Actions로 설정되지 않음 |
