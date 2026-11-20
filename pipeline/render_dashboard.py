"""Fill the fixed dashboard template with one day's CSVs + commentary.

Output: site/days/<date>.html, and site/index.html pointing at the latest day.
"""

import csv
import datetime as dt
import json
import math
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape

from pipeline import ai_summary, drilldown, fmt

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
BASIS = drilldown.BASIS
# Shown when hovering a KPI card: what is counted (docs/ops_bi/02_ops_metric_definitions.md).
DEFINITION = {
    "K01_revenue": "중복을 뺀 주문의 금액 합 (USD)",
    "K02_orders": "고유 주문 수. 같은 거래번호의 재전송은 1건",
    "K03_sessions": "그날 이벤트가 있는 세션 수 (사용자 ID + 세션 ID)",
    "K04_active_users": "그날 이벤트가 있는 고유 사용자 수",
    "K05_session_cvr": "주문이 1건 이상인 세션 ÷ 전체 세션",
    "K06_aov": "매출 ÷ 매출값이 있는 주문 수",
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
            "dod": fmt.change(r["unit"], r["dod_change"]),
            "wow": fmt.change(r["unit"], r["wow_day_change"]),
            "r7": fmt.change(r["unit"], r["r7_change"]),
            "definition": DEFINITION[mid],
            "mom": fmt.change(r["unit"], r["mom_change"]),
            "notable": r["flag"] == "notable",
            "spark": sparkline([series(t) for t in trend]),
        })

    last7 = trend[-7:]
    s = lambda k: sum(f(t[k]) or 0 for t in last7)
    # Cart is not a funnel step: many checkouts skip it ("buy now"). It is shown as a side metric.
    steps = [("세션", s("sessions")), ("상품 조회", s("view_item_sessions")),
             ("체크아웃", s("checkout_sessions")), ("구매", s("order_sessions"))]
    cart_rate = s("add_to_cart_sessions") / s("view_item_sessions") * 100 if s("view_item_sessions") else 0
    funnel = [{"label": n, "value": f"{v:,.0f}", "pct": v / steps[0][1] * 100 if steps[0][1] else 0,
               "step": "" if i == 0 or not steps[i - 1][1] else f"이전 단계 대비 {v / steps[i - 1][1] * 100:.1f}%"}
              for i, (n, v) in enumerate(steps)]

    segment_rows = read(run_dir / "segment.csv") if (run_dir / "segment.csv").exists() else []
    today = drilldown.today_items(comparison.values())
    if len(trend) >= 14:
        cur, prev = drilldown.window_sums(trend[-7:]), drilldown.window_sums(trend[-14:-7])
        where, segments = drilldown.where_lines(trend[-7:], trend[-14:-7], segment_rows)
        terms = drilldown.three_terms(cur, prev) if where else []
    else:
        where, segments, terms = [], [], []
    # Header trust line: calculation checks (R*) and data arrival only; quality warnings stay on their tab.
    blocking = [r for r in dq if (r["check_id"].startswith("R") or r["check_id"].startswith("DQ01"))
                and r["status"] == "FAIL"]

    detail = [{"name": r["metric_name"], "tier": r["tier"], "day": fmt.value(r["metric_id"], r["unit"], r["value_day"]),
               "dod": fmt.change(r["unit"], r["dod_change"]), "wow": fmt.change(r["unit"], r["wow_day_change"]),
               "r7": fmt.change(r["unit"], r["r7_change"]), "mom": fmt.change(r["unit"], r["mom_change"]),
               "flag": r["flag"]} for r in comparison.values()]

    dates = [t["kpi_date"] for t in trend]
    money = lambda v: f"${v:,.0f}"
    count = lambda v: f"{v:,.0f}"
    charts = {
        "revenue": line_chart("c-rev", dates, [f(t["revenue"]) for t in trend], "매출", money),
        "sessions": line_chart("c-ses", dates, [f(t["sessions"]) for t in trend], "세션", count),
    }

    text = ai_summary.readable(commentary, run_dir)
    if text:
        ai = {"ok": True, **text, "model": commentary.get("model", "")}
    else:
        ai = {"ok": False, "reason": commentary.get("reason", ""), "errors": commentary.get("errors", [])}

    days = sorted({p.stem for p in (SITE / "days").glob("*.html")} | {day}, reverse=True)
    d = dt.date.fromisoformat(day)
    env = Environment(loader=FileSystemLoader(ROOT / "templates"), autoescape=select_autoescape(["html", "j2"]))
    html = env.get_template("dashboard.html.j2").render(
        day=day, weekday="월화수목금토일"[d.weekday()], days=days,
        tiles=tiles, funnel=funnel,
        cart_rate=f"{cart_rate:.1f}%",
        today=today, where=where, terms=terms, segments=segments, verified=not blocking,
        detail=detail, charts=charts, ai=ai,
        dq=[{**r, "badge": DQ_BADGE[r["status"]]} for r in dq],
        generated=dt.datetime.now(dt.timezone(dt.timedelta(hours=9))).strftime("%Y-%m-%d %H:%M KST"),
    )
    (SITE / "days").mkdir(parents=True, exist_ok=True)
    page = SITE / "days" / f"{day}.html"
    page.write_text(html)
    if day == days[0]:
        (SITE / "index.html").write_text(
            f'<!doctype html><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=days/{day}.html">'
            f'<title>GA4 운영 리포트</title><a href="days/{day}.html">최신 리포트 ({day})</a>')
    render_report_list(env)
    return page


def render_report_list(env):
    """site/reports.html: one row per day with the AI headline and links."""
    rows = []
    for run_dir in sorted(RUNS.iterdir(), reverse=True):
        c_path = run_dir / "commentary.json"
        if not c_path.exists():
            continue
        c = json.loads(c_path.read_text())
        text = ai_summary.readable(c, run_dir)
        d = dt.date.fromisoformat(run_dir.name)
        rows.append({"day": run_dir.name, "weekday": "월화수목금토일"[d.weekday()],
                     "headline": text["headline"] if text else c.get("reason", ""), "ai_ok": bool(text)})
    html = env.get_template("reports.html.j2").render(
        rows=rows, generated=dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M UTC"))
    (SITE / "reports.html").write_text(html)
