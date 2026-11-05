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
from pathlib import Path

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

# Instructions for the comment live in an editable guide; the hard rules are also enforced by validate().
GUIDE = Path(__file__).resolve().parents[1] / "docs" / "ai_comment_guide.md"


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
        system=GUIDE.read_text(),
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
