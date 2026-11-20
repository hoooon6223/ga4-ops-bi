"""The two boxes at the top of the dashboard: what to look at today, and where it changed.

Both report what changed and where, never why. The tree they walk is
docs/ops_bi/03_metric_hierarchy.md: revenue -> five factors -> funnel steps -> segments.
"""

import math

from pipeline import fmt

BASIS = {"day_wow": "지난주 같은 요일 대비", "r7_wow": "최근 7일 vs 직전 7일"}

# Revenue = sessions x CVR x orders per order-session x revenue coverage x AOV (exact).
# The middle two only make the product exact; they are named only when they moved the most.
FACTORS = [
    ("세션", lambda t: t["sessions"], True),
    ("세션 전환율", lambda t: t["order_sessions"] / t["sessions"], True),
    ("세션당 주문 수", lambda t: t["orders"] / t["order_sessions"], False),
    ("매출 기록 비율", lambda t: t["orders_with_revenue"] / t["orders"], False),
    ("객단가", lambda t: t["revenue"] / t["orders_with_revenue"], True),
]
FUNNEL = [
    ("상품 조회율", "view_item_sessions", "sessions"),
    ("체크아웃 진입률", "checkout_sessions", "view_item_sessions"),
    ("결제 완료율", "order_sessions", "checkout_sessions"),
]
SEGMENT_LABEL = {"desktop": "데스크톱", "mobile": "모바일", "tablet": "태블릿", "organic": "자연 검색",
                 "(none)": "직접 방문", "referral": "외부 링크", "cpc": "검색 광고", "기타": "기타"}
MIN_SEGMENT_SESSIONS = 100  # 7-day sessions below this: too few to read a rate


def _f(x):
    return float(x) if x not in (None, "") else 0.0


def window_sums(days):
    keys = ["sessions", "order_sessions", "orders", "orders_with_revenue", "revenue",
            "view_item_sessions", "checkout_sessions"]
    return {k: sum(_f(d[k]) for d in days) for k in keys}


def _pct(v):
    return f"{v * 100:.1f}%"


def _pp(v, digits=2):
    """A rate difference in %p, without a "-0.00" for values that round to zero."""
    v = v * 100
    return f"{0.0 if abs(v) < 0.5 * 10 ** -digits else v:+.{digits}f}%p"


def today_items(comparison):
    """KPIs flagged notable, in the order of the KPI cards."""
    items = []
    for r in comparison:
        if r["tier"] == "1" and r["flag"] == "notable":
            items.append({"name": r["metric_name"], "change": fmt.change(r["unit"], r["flag_change"]),
                          "basis": BASIS[r["flag_basis"]], "up": _f(r["flag_change"]) > 0})
    return items


def three_terms(cur, prev):
    """Sessions, CVR and AOV changes for the headline line of the box."""
    rows = []
    for label, calc, main in FACTORS:
        if main:
            change = f"{calc(cur) / calc(prev) - 1:+.1%}"
            if label == "세션 전환율":
                change = f"{_pp(calc(cur) - calc(prev))} ({change})"
            rows.append({"label": label, "change": change})
    return rows


def segment_effects(segment_rows, dim):
    """Split the CVR change of one segment dimension into mix and rate effects (exact, in %p)."""
    rows = [r for r in segment_rows if r["dim"] == dim]
    if any(int(r["days"]) != 7 for r in rows):
        return None
    by = {}
    for r in rows:
        by.setdefault(r["val"], {})[r["w"]] = (_f(r["sessions"]), _f(r["order_sessions"]))
    by = {v: w for v, w in by.items() if "cur" in w and "prev" in w}
    s0 = sum(w["prev"][0] for w in by.values())
    s1 = sum(w["cur"][0] for w in by.values())
    if not s0 or not s1:
        return None
    mix = rate = inter = 0.0
    segs = []
    for v, w in by.items():
        (n0, o0), (n1, o1) = w["prev"], w["cur"]
        w0, w1 = n0 / s0, n1 / s1
        r0, r1 = (o0 / n0 if n0 else 0), (o1 / n1 if n1 else 0)
        mix += (w1 - w0) * r0
        rate += w0 * (r1 - r0)
        inter += (w1 - w0) * (r1 - r0)
        segs.append({"val": v, "label": SEGMENT_LABEL.get(v, v), "sessions": n1, "share": w1,
                     "share_change": w1 - w0, "cvr": r1, "cvr_change": r1 - r0,
                     "rate_effect": w0 * (r1 - r0), "small": n1 < MIN_SEGMENT_SESSIONS,
                     "cvr_change_pp": _pp(r1 - r0), "share_change_pp": _pp(w1 - w0, 1), "rate_effect_pp": _pp(w0 * (r1 - r0))})
    segs.sort(key=lambda s: -s["sessions"])
    return {"dim": dim, "mix": mix, "rate": rate, "inter": inter, "segments": segs,
            "mix_pp": _pp(mix), "rate_pp": _pp(rate), "inter_pp": _pp(inter)}


# 7-day thresholds, the same numbers as cfg in sql/pipeline/04_ops_kpi_comparison.sql.
# Every term is judged on the 7-day window here, sessions included (its card uses the same weekday).
L1_LIMITS = {"세션": ("rel", 0.20), "세션 전환율": ("pp", 0.0020), "객단가": ("rel", 0.15)}
FUNNEL_LIMITS = {"상품 조회율": 0.02, "체크아웃 진입률": 0.05, "결제 완료율": 0.05}


def _line(text, muted=False):
    return {"text": text, "muted": muted}


def _passes(label, c, p):
    kind, limit = L1_LIMITS[label]
    return abs(c / p - 1) > limit if kind == "rel" else abs(c - p) > limit


def _session_segments(segment_rows):
    parts = []
    for dim in ("기기", "유입 매체"):
        e = segment_effects(segment_rows, dim)
        if not e:
            continue
        prev_n = {r["val"]: _f(r["sessions"]) for r in segment_rows if r["dim"] == dim and r["w"] == "prev"}
        deltas = sorted(((s["sessions"] - prev_n.get(s["val"], 0), s["label"]) for s in e["segments"]),
                        key=lambda x: -abs(x[0]))[:2]
        parts.append(f"{dim}별 세션 증감 " + ", ".join(f"{lab} {d:+,.0f}" for d, lab in deltas))
    return parts


def _cvr_segments(segment_rows):
    parts = []
    for dim in ("기기", "유입 매체"):
        e = segment_effects(segment_rows, dim)
        if not e:
            continue
        big = [s for s in sorted(e["segments"], key=lambda s: -abs(s["rate_effect"])) if not s["small"]][:2]
        parts.append(f"{dim}: 구성 변화 {_pp(e['mix'])}, {dim} 안 전환율 변화 {_pp(e['rate'])} ("
                     + ", ".join(f"{s['label']} {_pp(s['rate_effect'])}" for s in big) + ")")
    return parts


def where_lines(cur_days, prev_days, segment_rows):
    """Plain sentences walking down the tree from revenue, on the 7-day window. Facts only.

    Every L1 term past its threshold is named (largest change first); the segments are shown
    for the first one. Funnel steps past their threshold are named even when CVR itself is not.
    With nothing past a threshold, the largest move is shown greyed out as a reference.
    """
    cur, prev = window_sums(cur_days), window_sums(prev_days)
    needed = ["sessions", "order_sessions", "orders", "orders_with_revenue", "revenue"]
    if any(cur[k] <= 0 or prev[k] <= 0 for k in needed):
        return [], []
    calcs = {label: calc for label, calc, _ in FACTORS}
    move = lambda label: abs(math.log(calcs[label](cur) / calcs[label](prev)))
    change = lambda label: f"{calcs[label](cur) / calcs[label](prev) - 1:+.1%}"

    passed = sorted((l for l in L1_LIMITS if _passes(l, calcs[l](cur), calcs[l](prev))), key=move, reverse=True)
    steps = [(label, cur[n] / cur[d], prev[n] / prev[d]) for label, n, d in FUNNEL
             if cur[n] and cur[d] and prev[n] and prev[d]]
    hot_steps = [(l, c, p) for l, c, p in steps if abs(c - p) > FUNNEL_LIMITS[l]]

    revenue = f"매출 {cur['revenue'] / prev['revenue'] - 1:+.1%} (최근 7일 vs 직전 7일)."
    lines = [_line(revenue + (" 판정 기준을 넘은 항: " + ", ".join(passed) + "." if passed
                              else " 판정 기준을 넘은 항 없음."))]

    # Segments go under the first passed term that has children (AOV has none in the mart).
    with_segments = next((l for l in passed if l in ("세션", "세션 전환율")), None)
    for label in passed:
        if label == "세션 전환율":
            c, p = calcs[label](cur), calcs[label](prev)
            text = f"세션 전환율 {p * 100:.2f}% → {c * 100:.2f}% ({_pp(c - p)})"
            if hot_steps:
                text += ". 기준을 넘은 퍼널 단계: " + ", ".join(f"{l} {_pp(c2 - p2)}" for l, c2, p2 in hot_steps)
            elif steps:
                l, c2, p2 = max(steps, key=lambda s: abs(math.log(s[1] / s[2])))
                text += f". 가장 크게 변한 퍼널 단계: {l} {_pp(c2 - p2)}"
            lines.append(_line(text + "."))
            if label == with_segments:
                lines += [_line(t + ".") for t in _cvr_segments(segment_rows)]
        else:
            lines.append(_line(f"{label} {change(label)}."))
            if label == with_segments:
                lines += [_line(t + ".") for t in _session_segments(segment_rows)]

    if "세션 전환율" not in passed and hot_steps:
        c, p = calcs["세션 전환율"](cur), calcs["세션 전환율"](prev)
        lines.append(_line(f"세션 전환율은 기준 안쪽({_pp(c - p)})이지만 퍼널 단계는 기준을 넘음: "
                           + ", ".join(f"{l} {_pp(c2 - p2)}" for l, c2, p2 in hot_steps) + "."))

    if not passed and not hot_steps:
        top = max(L1_LIMITS, key=move)
        lines.append(_line(f"참고: 변화율이 가장 큰 항은 {top} ({change(top)}).", muted=True))

    # The two bridge terms have no threshold; they are named when they moved more than every L1 term.
    largest = max(move(l) for l in L1_LIMITS)
    for label, calc, main in FACTORS:
        if not main and move(label) > largest:
            lines.append(_line(f"보정 항 {label}이 더 크게 움직임 ({change(label)}). "
                               "주문 기록 방식에 따라 움직이는 항이라 데이터 품질 탭을 함께 확인하세요."))

    segments = [e for e in (segment_effects(segment_rows, d) for d in ("기기", "유입 매체")) if e]
    return lines, segments
