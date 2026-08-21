# 프로젝트 관리

## BigQuery

현재 Google Cloud project:

```text
bigquery-457902
```

Dataset 구조:

```text
bigquery-457902
├── basic
│   ├── battle
│   ├── pockemon
│   └── trainer
└── ga4_ops_bi
    ├── daily_kpi_mart
    ├── daily_funnel_mart
    └── daily_segment_mart
```

결정 사항:
- 포트폴리오 프로젝트는 별도 dataset인 `ga4_ops_bi`에서 관리한다.
- 기존 연습용 dataset인 `basic`과 섞지 않는다.
- `sql/build_tables.sql`을 관리용 mart table 재생성 스크립트로 사용한다.

## 로컬 프로젝트

로컬 경로:

```text
/Users/hyeon/Documents/ChatGPT/데이터 분석/ga4_ops_bi
```

권장 repo 구성:
- `README.md`
- `sql/`
- `docs/`
- `data/`

메모:
- `data/` 안의 CSV 파일은 Tableau에 바로 연결할 수 있는 export 파일이다.
- Tableau workbook이나 큰 dashboard export 파일은 필요 시 `.gitignore`로 제외한다.

## GitHub

GitHub repo:

```text
https://github.com/hoooon6223/ga4-ops-bi
```

상태:
- GitHub CLI 인증 완료
- Remote `origin` 연결 완료
- `main` branch push 완료
- Repository visibility: private

기본 관리 흐름:

```bash
cd "/Users/hyeon/Documents/ChatGPT/데이터 분석/ga4_ops_bi"
git status
git add .
git commit -m "Update GA4 operations BI project"
git push
```
