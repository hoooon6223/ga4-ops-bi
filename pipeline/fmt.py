"""Number formatting shared by the AI summary (placeholder fill) and the dashboard."""

import re

# How each metric's value is shown. Changes follow the metric's unit in kpi_comparison.csv.
MONEY = {"K01_revenue", "K06_aov"}
CHANGE_FIELDS = {"dod_change", "wow_day_change", "r7_change", "mom_change"}
# Current values and the base values they are compared with (so a comment can say "last week was 0.00%").
VALUE_FIELDS = {"value_day", "r7_value", "mtd_value", "prev_day", "same_dow_last_week", "r7_prev", "mtd_prev_month"}
PLACEHOLDER = re.compile(r"\{\{\s*([A-Z0-9a-z_]+)\.([a-z0-9_]+)\s*\}\}")


def num(x):
    return None if x in (None, "") else float(x)


def value(metric_id, unit, x):
    x = num(x)
    if x is None:
        return "–"
    if unit == "rate":
        return f"{x * 100:.2f}%"
    if metric_id in MONEY:
        return f"${x:,.2f}" if metric_id == "K06_aov" else f"${x:,.0f}"
    return f"{x:,.0f}"


def change(unit, x):
    x = num(x)
    if x is None:
        return "–"
    return f"{x:+.2f}%p" if unit == "rate" else f"{x * 100:+.1f}%"


def placeholder_table(comparison_rows, dq_rows):
    """{(id, field): formatted text} for every non-empty number the AI may cite."""
    table = {}
    for r in comparison_rows:
        for f in VALUE_FIELDS | CHANGE_FIELDS:
            if r.get(f) not in (None, ""):
                text = change(r["unit"], r[f]) if f in CHANGE_FIELDS else value(r["metric_id"], r["unit"], r[f])
                table[(r["metric_id"], f)] = text
    for r in dq_rows:
        if r.get("value") not in (None, "") and r["check_id"].startswith("DQ"):
            v = float(r["value"])
            table[(r["check_id"], "value")] = f"{v * 100:.1f}%" if abs(v) <= 1.5 else f"{v:,.0f}"
    return table


def fill(text, table):
    return PLACEHOLDER.sub(lambda m: table.get((m.group(1), m.group(2)), m.group(0)), text)
