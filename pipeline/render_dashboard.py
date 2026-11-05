"""Fill the fixed dashboard template with one day's CSVs + commentary.

Output: site/days/<date>.html, and site/index.html pointing at the latest day.
"""

import csv
import datetime as dt
import json
import math
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

from pipeline import fmt

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "site"
RUNS = ROOT / "outputs" / "runs"

TILES = [  # metric_id, label, how to compute the 28-day sparkline from kpi_daily
    ("K01_revenue", "매출", lambda r: f(r["revenue"])),
    ("K02_orders", "주문 수", lambda r: f(r["orders"])),
    ("K03_sessions", "세션", lambda r: f(r["sessions"])),
    ("K04_active_users", "활성 사용자", lambda r: f(r["active_users"])),
    ("K05_session_cvr", "세션 전환율", lambda r: ratio(r["order_sessions"], r["sessions"])),
    ("K06_aov", "객단가", lambda r: ratio(r["revenue"], r["orders_with_revenue"])),
]
BASIS = {"day_wow": "지난주 같은 요일 대비", "r7_wow": "최근 7일 vs 직전 7일"}
STATUS = {
    "normal": ("good", "✓", "정상", "데이터 품질 체크를 모두 통과했어요."),
    "caution": ("warning", "!", "주의", "일부 품질 체크에 경고가 있어요. 관련 지표는 해석에 주의하세요."),
    "hold": ("critical", "✕", "해석 보류", "품질 체크가 실패했어요. 오늘 숫자는 해석을 보류하세요."),
}
DQ_BADGE = {"PASS": ("good", "✓", "통과"), "WARN": ("warning", "!", "경고"),
            "FAIL": ("critical", "✕", "실패"), "SKIP": ("muted", "–", "건너뜀")}


def f(x):
    return float(x) if x not in (None, "") else None


def ratio(a, b):
    a, b = f(a), f(b)
    return a / b if a is not None and b else None


def read(path):
    with open(path, newline="") as fh:
        return list(csv.DictReader(fh))


def sparkline(values, w=120, h=32):
    pts = [(i, v) for i, v in enumerate(values) if v is not None]
    if len(pts) < 2:
        return ""
    lo, hi = min(v for _, v in pts), max(v for _, v in pts)
    span = (hi - lo) or 1
    xy = [(i * w / (len(values) - 1), h - 3 - (v - lo) / span * (h - 6)) for i, v in pts]
    line = " ".join(f"{x:.1f},{y:.1f}" for x, y in xy)
    lx, ly = xy[-1]
    return (f'<svg class="spark" viewBox="0 0 {w} {h}" width="{w}" height="{h}" aria-hidden="true">'
            f'<polyline points="{line}" fill="none" class="spark-line"/>'
            f'<circle cx="{lx:.1f}" cy="{ly:.1f}" r="3" class="spark-dot"/></svg>')


def line_chart(chart_id, dates, values, label, unit_fmt, w=560, h=200):
    """Single-series line chart; a small script adds the crosshair + tooltip."""
    pad_l, pad_r, pad_t, pad_b = 52, 12, 12, 26
    vals = [v for v in values if v is not None]
    raw_step = (max(vals) if vals else 1) / 4
    mag = 10 ** math.floor(math.log10(raw_step)) if raw_step > 0 else 1
    step = next(m * mag for m in (1, 2, 2.5, 5, 10) if m * mag >= raw_step)
    hi = step * 4  # 4 round gridlines that cover the max
    x = lambda i: pad_l + i * (w - pad_l - pad_r) / max(len(values) - 1, 1)
    y = lambda v: pad_t + (1 - v / hi) * (h - pad_t - pad_b)
    grid = "".join(
        f'<line x1="{pad_l}" x2="{w - pad_r}" y1="{y(hi * k / 4):.1f}" y2="{y(hi * k / 4):.1f}" class="grid"/>'
        f'<text x="{pad_l - 6}" y="{y(hi * k / 4) + 4:.1f}" class="tick" text-anchor="end">{unit_fmt(hi * k / 4)}</text>'
        for k in range(1, 5))
    xt = "".join(f'<text x="{x(i):.1f}" y="{h - 6}" class="tick" text-anchor="middle">{d[5:]}</text>'
                 for i, d in enumerate(dates) if i % 7 == (len(dates) - 1) % 7)
    pts = " ".join(f"{x(i):.1f},{y(v):.1f}" for i, v in enumerate(values) if v is not None)
    data = json.dumps({"x": [round(x(i), 1) for i in range(len(values))], "dates": dates,
                       "labels": [unit_fmt(v) if v is not None else "–" for v in values],
                       "y": [round(y(v), 1) if v is not None else None for v in values]})
    return (f'<svg id="{chart_id}" class="chart" viewBox="0 0 {w} {h}" role="img" aria-label="{label} 최근 28일 추이" '
            f"data-points='{data}'>"
            f'<line x1="{pad_l}" x2="{w - pad_r}" y1="{y(0):.1f}" y2="{y(0):.1f}" class="axis"/>{grid}{xt}'
            f'<polyline points="{pts}" fill="none" class="series"/>'
            f'<line class="xhair" y1="{pad_t}" y2="{h - pad_b}" x1="-10" x2="-10"/>'
            f'<circle class="xdot" r="4" cx="-10" cy="-10"/>'
            f'<rect class="hit" x="{pad_l}" y="0" width="{w - pad_l - pad_r}" height="{h}" fill="transparent"/></svg>')


def render(run_dir):
    day = run_dir.name
    comparison = {r["metric_id"]: r for r in read(run_dir / "kpi_comparison.csv")}
    dq = read(run_dir / "dq_results.csv")
    trend = read(run_dir / "trend.csv")
    commentary = json.loads((run_dir / "commentary.json").read_text())
    table = fmt.placeholder_table(comparison.values(), dq)

    tiles = []
    for mid, label, series in TILES:
        r = comparison[mid]
        tiles.append({
            "label": label,
            "value": fmt.value(mid, r["unit"], r["value_day"]),
            "delta": fmt.change(r["unit"], r["flag_change"]),
            "delta_sign": (f(r["flag_change"]) or 0),
            "basis": BASIS[r["flag_basis"]],
            "wow": fmt.change(r["unit"], r["wow_day_change"]),
            "mom": fmt.change(r["unit"], r["mom_change"]),
            "notable": r["flag"] == "notable",
            "spark": sparkline([series(t) for t in trend]),
        })

    last7 = trend[-7:]
    s = lambda k: sum(f(t[k]) or 0 for t in last7)
    steps = [("세션", s("sessions")), ("상품 조회", s("view_item_sessions")), ("장바구니", s("add_to_cart_sessions")),
             ("체크아웃", s("checkout_sessions")), ("구매", s("order_sessions"))]
    funnel = [{"label": n, "value": f"{v:,.0f}", "pct": v / steps[0][1] * 100 if steps[0][1] else 0,
               "step": "" if i == 0 or not steps[i - 1][1] else f"이전 단계 대비 {v / steps[i - 1][1] * 100:.1f}%"}
              for i, (n, v) in enumerate(steps)]
    funnel_warn = any(r["check_id"] == "DQ08_funnel_tracking" and r["status"] == "WARN" for r in dq)

    decomposition = [
        {"label": "세션 (7일 합)", "value": table.get(("K03_sessions", "r7_value"), "–"), "change": table.get(("K03_sessions", "r7_change"), "–")},
        {"label": "세션 전환율", "value": table.get(("K05_session_cvr", "r7_value"), "–"), "change": table.get(("K05_session_cvr", "r7_change"), "–")},
        {"label": "객단가", "value": table.get(("K06_aov", "r7_value"), "–"), "change": table.get(("K06_aov", "r7_change"), "–")},
        {"label": "매출 (7일 합)", "value": table.get(("K01_revenue", "r7_value"), "–"), "change": table.get(("K01_revenue", "r7_change"), "–")},
    ]

    funnel_hold = {"D02_add_to_cart_rate", "D03_checkout_rate"} if funnel_warn else set()  # DQ08: not interpretable
    detail = [{"name": r["metric_name"], "tier": r["tier"], "day": fmt.value(r["metric_id"], r["unit"], r["value_day"]),
               "dod": fmt.change(r["unit"], r["dod_change"]), "wow": fmt.change(r["unit"], r["wow_day_change"]),
               "r7": fmt.change(r["unit"], r["r7_change"]), "mom": fmt.change(r["unit"], r["mom_change"]),
               "flag": "hold" if r["metric_id"] in funnel_hold else r["flag"]} for r in comparison.values()]

    dates = [t["kpi_date"] for t in trend]
    money = lambda v: f"${v:,.0f}"
    count = lambda v: f"{v:,.0f}"
    charts = {
        "revenue": line_chart("c-rev", dates, [f(t["revenue"]) for t in trend], "매출", money),
        "sessions": line_chart("c-ses", dates, [f(t["sessions"]) for t in trend], "세션", count),
    }

    if commentary.get("ok"):
        ai = {"ok": True, "headline": fmt.fill(commentary["headline"], table),
              "highlights": [{**h, "text": fmt.fill(h["text"], table)} for h in commentary["highlights"]],
              "watch_items": [fmt.fill(w, table) for w in commentary["watch_items"]],
              "dq_note": fmt.fill(commentary["data_quality_note"], table), "model": commentary.get("model", "")}
    else:
        ai = {"ok": False, "reason": commentary.get("reason", ""), "errors": commentary.get("errors", [])}

    days = sorted({p.stem for p in (SITE / "days").glob("*.html")} | {day}, reverse=True)
    d = dt.date.fromisoformat(day)
    env = Environment(loader=FileSystemLoader(ROOT / "templates"), autoescape=select_autoescape(["html", "j2"]))
    html = env.get_template("dashboard.html.j2").render(
        day=day, weekday="월화수목금토일"[d.weekday()], days=days,
        status=STATUS[commentary["status"]], tiles=tiles, funnel=funnel, funnel_warn=funnel_warn,
        decomposition=decomposition, detail=detail, charts=charts, ai=ai,
        dq=[{**r, "badge": DQ_BADGE[r["status"]]} for r in dq],
        generated=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
    )
    (SITE / "days").mkdir(parents=True, exist_ok=True)
    page = SITE / "days" / f"{day}.html"
    page.write_text(html)
    if day == days[0]:
        (SITE / "index.html").write_text(
            f'<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=days/{day}.html">'
            f'<title>GA4 운영 리포트</title><a href="days/{day}.html">최신 리포트 ({day})</a>')
    return page
