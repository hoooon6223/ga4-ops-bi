# Project Management

## BigQuery

Current Google Cloud project:

```text
bigquery-457902
```

Dataset layout:

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

Decision:
- Keep the portfolio project in its own dataset: `ga4_ops_bi`.
- Do not mix it with the existing `basic` practice dataset.
- Use `sql/build_tables.sql` as the reproducible build script for managed mart tables.

## Local Project

Local path:

```text
/Users/hyeon/Documents/ChatGPT/데이터 분석/ga4_ops_bi
```

Recommended repo contents:
- `README.md`
- `sql/`
- `docs/`
- `data/`

Note:
- CSV files in `data/` are Tableau-ready exports.
- If the GitHub repo should stay lightweight, large dashboard exports can be excluded later with `.gitignore`.

## GitHub

GitHub CLI is installed, but authentication is not complete yet.

To finish authentication from a normal terminal:

```bash
gh auth login
```

Recommended answers:
- GitHub.com
- HTTPS
- Authenticate Git with GitHub credentials: Yes
- Login with a web browser

After login, this project can be published with:

```bash
cd "/Users/hyeon/Documents/ChatGPT/데이터 분석"
git init
git add ga4_ops_bi
git commit -m "Add GA4 operations BI portfolio project"
gh repo create ga4-ops-bi --private --source=. --remote=origin --push
```

