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
# One fact per sentence: endings that join two facts ("rose, so ...", "warning, therefore ...") are rejected too.
LINKING = re.compile(r"해서|하여|라서|이라[\s,]|므로|니까|면서|고 있어|\S(으로|로)\s")
SPELLED_NUMBER = re.compile(r"(^|\s)(영|제로)(\s|이|으|$)")
# Data-quality results live on the dashboard's quality tab only, never in the comment.
QUALITY = re.compile(r"품질|해석 보류|누락|WARN|FAIL|경고")
RAW_LABEL = re.compile(r"\b(notable|normal)\b|\b(K|D|DQ)\d{2}_[a-z_]+")

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
    },
    "required": ["headline", "highlights", "watch_items"],
    "additionalProperties": False,
}

# Instructions for the comment live in an editable guide; the hard rules are also enforced by validate().
GUIDE = Path(__file__).resolve().parents[1] / "docs" / "ai_comment_guide.md"


def _read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def validate(c, table, metric_ids):
    errors = []
    texts = [c["headline"], *c["watch_items"], *(h["text"] for h in c["highlights"])]
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
        plain = fmt.PLACEHOLDER.sub("", t)
        if LINKING.search(plain):
            errors.append(f"두 사실을 잇는 연결 어미를 씀 ('{LINKING.search(plain).group(0).strip()}'): {t}")
        if SPELLED_NUMBER.search(plain):
            errors.append(f"숫자를 글자로 씀: {t}")
        if RAW_LABEL.search(plain):
            errors.append(f"영어 판정값이나 지표 ID를 그대로 씀: {t}")
        if QUALITY.search(plain):
            errors.append(f"데이터 품질 이야기를 씀 (품질 결과는 데이터 품질 탭에만 표시): {t}")
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
    table = fmt.placeholder_table(_read(run_dir / "kpi_comparison.csv"), [])
    return {
        "headline": fmt.fill(commentary["headline"], table),
        "highlights": [fmt.fill(h["text"], table) for h in commentary["highlights"]],
        "watch_items": [fmt.fill(w, table) for w in commentary["watch_items"]],
    }


def summarize(run_dir):
    # The AI sees only the KPI comparison table; quality-check results are not sent.
    comparison = _read(run_dir / "kpi_comparison.csv")
    table = fmt.placeholder_table(comparison, [])
    metric_ids = {r["metric_id"] for r in comparison}
    day = dt.date.fromisoformat(run_dir.name)

    user_text = (
        f"리포트 날짜: {day} ({'월화수목금토일'[day.weekday()]}요일)\n"
        f"[kpi_comparison.csv]\n{(run_dir / 'kpi_comparison.csv').read_text()}\n"
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
        return {"ok": False, "reason": _friendly(e)}

    if errors:
        return {"ok": False, "reason": "AI 요약이 숫자 검증을 통과하지 못했어요.", "errors": errors}
    return {"ok": True, "model": MODEL, **c}
