"""Claude writes the daily comment. Numbers never come from the model.

The model may only cite numbers through placeholders like {{K01_revenue.r7_change}};
the dashboard fills them from the SQL output. validate() rejects any bare digit,
any placeholder that does not point to a real value, and unknown metric ids.
"""

import csv
import datetime as dt
import json
import os
import re

import anthropic

from pipeline import fmt

MODEL = os.environ.get("CLAUDE_MODEL", "claude-opus-5-5")
ALLOWED_DIGIT_PHRASES = re.compile(r"(최근\s*)?(7|28)일")
# The comment reports what changed, not why. Cause, effect and guess words are rejected.
CAUSAL_WORDS = ["요인", "영향", "원인", "때문", "덕분", "인해", "기인", "견인", "주도", "가능성", "추정", "수 있"]

SCHEMA = {
    "type": "object",
    "properties": {
        "headline": {"type": "string"},
        "highlights": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "metric_id": {"type": "string"},
                    "direction": {"type": "string", "enum": ["up", "down", "flat"]},
                    "text": {"type": "string"},
                },
                "required": ["metric_id", "direction", "text"],
                "additionalProperties": False,
            },
        },
        "watch_items": {"type": "array", "items": {"type": "string"}},
        "data_quality_note": {"type": "string"},
    },
    "required": ["headline", "highlights", "watch_items", "data_quality_note"],
    "additionalProperties": False,
}

SYSTEM = """당신은 이커머스 운영팀의 데이터 분석가입니다. 매일 아침 KPI 리포트의 코멘트를 씁니다.
코멘트는 현상만 기록합니다. 어떤 지표가, 무엇과 비교해, 얼마나 변했는지만 쓰고 원인이나 해석은 쓰지 않습니다.

규칙
1. 숫자를 직접 쓰지 마세요. 숫자가 필요하면 반드시 자리표시를 쓰세요: {{지표ID.필드}}
   - 예: "매출이 최근 7일 기준 {{K01_revenue.r7_change}} 변했어요."
   - 사용할 수 있는 자리표시는 아래 '사용 가능한 자리표시' 목록에 있는 것뿐입니다.
   - 예외로 "7일", "28일"이라는 기간 표현만 숫자를 그대로 써도 됩니다.
2. 판단 기준은 flag 열입니다. flag가 notable인 지표를 우선 다루고, normal인 지표는 필요할 때만 언급하세요.
   - 비교 기준(flag_basis): day_wow = 지난주 같은 요일 대비, r7_wow = 최근 7일 vs 직전 7일.
   - 전일 대비(dod)는 요일 효과가 커서 판단 근거로 쓰지 마세요.
3. 리포트 상태(status)가 hold면, headline에 "데이터 품질 체크 실패로 해석 보류"라고 쓰고 실패한 체크 이름을 적으세요.
   caution이면 WARN이 뜬 품질 체크 이름과 값을 적으세요.
   품질 체크와 관련된 지표는 아래 정의 규칙에 있는 것만 "해석 보류"라고 표시하세요:
   - DQ03_null_revenue가 WARN/FAIL이면 매출(K01)과 객단가(K06)는 해석 보류.
   - DQ08_funnel_tracking이 WARN이면 장바구니율(D02)은 해석 보류.
   퍼널은 상품 조회 → 체크아웃 → 구매이고, 장바구니는 퍼널 단계가 아닌 별도 지표예요.
4. 원인, 영향, 추측을 쓰지 마세요.
   - 금지 표현: 요인, 영향, 원인, 때문, 덕분, 인해, 기인, 견인, 주도, 가능성, 추정, "~일 수 있어요".
   - 여러 지표가 함께 변했어도 서로 연결하지 말고 각각 따로 쓰세요.
     나쁜 예: "주문 증가는 전환율 상승에서 나왔어요." 좋은 예: "주문 수 {{K02_orders.r7_change}}, 세션 전환율 {{K05_session_cvr.r7_change}}."
5. 각 항목의 내용:
   - headline: 오늘 판정이 notable인 지표 이름과 방향을 한 문장으로.
   - highlights: notable 지표의 변화 (지표, 비교 기준, 변화량).
   - watch_items: 다음 리포트에서도 확인할 지표와 그 이유 (임계치 초과, 품질 경고, 비교 기준 없음 같은 사실만).
   - data_quality_note: 품질 체크 결과 요약 (WARN/FAIL인 체크 이름과 값, 해석 보류 대상 지표).
6. 분량: headline 1문장, highlights 최대 3개, watch_items 최대 3개, data_quality_note 1~2문장.
   해요체로, 짧고 분명하게 쓰세요."""


def _read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def status_of(dq_rows):
    statuses = {r["status"] for r in dq_rows}
    return "hold" if "FAIL" in statuses else "caution" if "WARN" in statuses else "normal"


def validate(c, table, metric_ids):
    errors = []
    texts = [c["headline"], c["data_quality_note"], *c["watch_items"], *(h["text"] for h in c["highlights"])]
    for t in texts:
        for m in fmt.PLACEHOLDER.finditer(t):
            if (m.group(1), m.group(2)) not in table:
                errors.append(f"없는 자리표시: {m.group(0)}")
        bare = ALLOWED_DIGIT_PHRASES.sub("", fmt.PLACEHOLDER.sub("", t))
        if re.search(r"\d", bare):
            errors.append(f"자리표시 없이 숫자를 씀: {t}")
        found = [w for w in CAUSAL_WORDS if w in t]
        if found:
            errors.append(f"원인·추측 표현을 씀 ({', '.join(found)}): {t}")
    for h in c["highlights"]:
        if h["metric_id"] not in metric_ids:
            errors.append(f"없는 지표: {h['metric_id']}")
    if len(c["highlights"]) > 3 or len(c["watch_items"]) > 3:
        errors.append("highlights 또는 watch_items가 3개를 넘음")
    return errors


def _ask(client, user_text):
    resp = client.beta.messages.create(
        model=MODEL,
        max_tokens=16000,
        system=SYSTEM,
        messages=[{"role": "user", "content": user_text}],
        output_config={"effort": "medium", "format": {"type": "json_schema", "schema": SCHEMA}},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )
    if resp.stop_reason == "refusal":
        raise RuntimeError(f"Claude declined: {resp.stop_details}")
    if resp.stop_reason == "max_tokens":
        raise RuntimeError("Claude response hit max_tokens")
    return json.loads(next(b.text for b in resp.content if b.type == "text"))


def _friendly(e):
    if isinstance(e, anthropic.AuthenticationError):
        why = "API 키 인증에 실패했어요"
    elif isinstance(e, anthropic.RateLimitError):
        why = "API 요청 한도를 넘었어요"
    elif isinstance(e, anthropic.APIConnectionError):
        why = "API 서버에 연결하지 못했어요"
    elif isinstance(e, anthropic.APIStatusError):
        why = f"API 오류가 났어요 (코드 {e.status_code})"
    else:
        why = "응답을 쓸 수 없었어요"
    return f"AI 코멘트를 만들지 못했어요. {why}."


def readable(commentary, run_dir):
    """The comment with numbers filled in from the day's CSVs (for the dashboard and the stored report)."""
    if not commentary.get("ok"):
        return None
    table = fmt.placeholder_table(_read(run_dir / "kpi_comparison.csv"), _read(run_dir / "dq_results.csv"))
    return {
        "headline": fmt.fill(commentary["headline"], table),
        "highlights": [fmt.fill(h["text"], table) for h in commentary["highlights"]],
        "watch_items": [fmt.fill(w, table) for w in commentary["watch_items"]],
        "data_quality_note": fmt.fill(commentary["data_quality_note"], table),
    }


def summarize(run_dir):
    comparison = _read(run_dir / "kpi_comparison.csv")
    dq = _read(run_dir / "dq_results.csv")
    table = fmt.placeholder_table(comparison, dq)
    metric_ids = {r["metric_id"] for r in comparison}
    status = status_of(dq)
    day = dt.date.fromisoformat(run_dir.name)

    user_text = (
        f"리포트 날짜: {day} ({'월화수목금토일'[day.weekday()]}요일)\n"
        f"리포트 상태(status): {status}\n\n"
        f"[kpi_comparison.csv]\n{(run_dir / 'kpi_comparison.csv').read_text()}\n"
        f"[dq_results.csv]\n{(run_dir / 'dq_results.csv').read_text()}\n"
        "사용 가능한 자리표시:\n" + "\n".join(f"{{{{{i}.{f}}}}}" for i, f in sorted(table))
    )

    client = anthropic.Anthropic()
    try:
        c = _ask(client, user_text)
        errors = validate(c, table, metric_ids)
        if errors:  # one retry with the reasons
            c = _ask(client, user_text + "\n\n이전 답변이 아래 이유로 거절됐어요. 규칙을 지켜 다시 써주세요:\n- "
                     + "\n- ".join(errors))
            errors = validate(c, table, metric_ids)
    except (anthropic.APIError, RuntimeError) as e:
        print(f"AI summary failed: {e!r}")  # full detail stays in the run log, not on the page
        return {"ok": False, "status": status, "reason": _friendly(e)}

    if errors:
        return {"ok": False, "status": status, "reason": "AI 요약이 숫자 검증을 통과하지 못했어요.", "errors": errors}
    return {"ok": True, "status": status, "model": MODEL, **c}
