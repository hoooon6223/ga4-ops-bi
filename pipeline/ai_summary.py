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

규칙
1. 숫자를 직접 쓰지 마세요. 숫자가 필요하면 반드시 자리표시를 쓰세요: {{지표ID.필드}}
   - 예: "매출이 최근 7일 기준 {{K01_revenue.r7_change}} 변했어요."
   - 사용할 수 있는 자리표시는 아래 '사용 가능한 자리표시' 목록에 있는 것뿐입니다.
   - 예외로 "7일", "28일"이라는 기간 표현만 숫자를 그대로 써도 됩니다.
2. 판단 기준은 flag 열입니다. flag가 notable인 지표를 우선 다루고, normal인 지표는 필요할 때만 언급하세요.
   - 비교 기준(flag_basis): day_wow = 지난주 같은 요일 대비, r7_wow = 최근 7일 vs 직전 7일.
   - 전일 대비(dod)는 요일 효과가 커서 판단 근거로 쓰지 마세요.
3. 리포트 상태(status)가 hold면, 숫자 해석을 하지 말고 headline에서 데이터 품질 문제로 해석을 보류한다고 쓰세요.
   caution이면 WARN이 뜬 품질 체크와 관련된 지표는 해석에 주의가 필요하다고 덧붙이세요.
   DQ08_funnel_tracking이 WARN이면 장바구니율(D02)과 체크아웃 진입률(D03)은 해석하지 마세요.
4. 원인은 데이터로 확인된 것만 말하고, 추정이면 "가능성"이라고 쓰세요.
5. 분량: headline 1문장, highlights 최대 3개, watch_items 최대 3개, data_quality_note 1~2문장.
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
        return {"ok": False, "status": status, "reason": f"AI 요약 실패: {e}"}

    if errors:
        return {"ok": False, "status": status, "reason": "AI 요약이 숫자 검증을 통과하지 못했어요.", "errors": errors}
    return {"ok": True, "status": status, "model": MODEL, **c}
