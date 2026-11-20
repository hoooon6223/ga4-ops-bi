"""Daily ops BI run: aggregate one replay day -> CSVs -> Claude summary -> dashboard.

Usage:
  python -m pipeline.run_daily              # next day after the last loaded day
  python -m pipeline.run_daily --date 2020-12-14
  python -m pipeline.run_daily --skip-ai    # no Claude call (numbers only)
"""

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

from pipeline import bq

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql" / "pipeline"
RUNS_DIR = ROOT / "outputs" / "runs"
DS = "`bigquery-457902.ga4_ops_bi"
REPLAY_START = dt.date(2020, 11, 1)
REPLAY_END = dt.date(2021, 1, 31)

EXPORTS = {
    "kpi_daily.csv": f"SELECT * EXCEPT(loaded_at) FROM {DS}.ops_kpi_daily` WHERE kpi_date = @run_date",
    "kpi_comparison.csv": f"SELECT * EXCEPT(loaded_at) FROM {DS}.ops_kpi_comparison` WHERE kpi_date = @run_date ORDER BY tier, metric_id",
    "dq_results.csv": f"SELECT * EXCEPT(loaded_at) FROM {DS}.ops_dq_results` WHERE dq_date = @run_date ORDER BY check_id",
    "trend.csv": f"SELECT * EXCEPT(loaded_at) FROM {DS}.ops_kpi_daily` "
                 "WHERE kpi_date BETWEEN DATE_SUB(@run_date, INTERVAL 27 DAY) AND @run_date ORDER BY kpi_date",
    # Segments for the "where did it change" box: last 7 days (cur) vs the 7 before (prev).
    # Obfuscated mediums (<Other>, (data deleted)) and small ones are grouped as 기타.
    "segment.csv": f"""
        SELECT dim, val, IF(session_date > DATE_SUB(@run_date, INTERVAL 7 DAY), 'cur', 'prev') AS w,
          COUNT(DISTINCT session_date) AS days, COUNT(*) AS sessions, COUNTIF(orders > 0) AS order_sessions
        FROM {DS}.ops_f_sessions`,
          UNNEST([STRUCT('기기' AS dim, IFNULL(device_category, '기타') AS val),
                  ('유입 매체', IF(medium IN ('organic', '(none)', 'referral', 'cpc'), medium, '기타'))])
        WHERE session_date BETWEEN DATE_SUB(@run_date, INTERVAL 13 DAY) AND @run_date
        GROUP BY dim, val, w ORDER BY dim, val, w""",
}


def next_run_date():
    # A day counts as done only when the last step (quality checks) is written, so a run that
    # failed partway is retried on the next run instead of being skipped.
    try:
        last = bq.rows(bq.query_csv(f"SELECT MAX(dq_date) AS d FROM {DS}.ops_dq_results`"))[0]["d"]
    except RuntimeError as e:
        if "Not found" not in str(e):
            raise
        last = ""
    if not last:
        return REPLAY_START
    nxt = dt.date.fromisoformat(last) + dt.timedelta(days=1)
    return nxt if nxt <= REPLAY_END else None


class Blocked(Exception):
    """A day that failed a blocking check (DQ01 or an R check): nothing was loaded."""


def day_script():
    """Steps 01-05 as one transaction. The gate at the end of 05 raises on a blocking FAIL,
    which rolls back every table, so a bad day is never half-loaded or published."""
    steps = "\n".join(p.read_text() for p in sorted(SQL_DIR.glob("0[1-5]_*.sql")))
    return f"BEGIN TRANSACTION;\n\n{steps}\nCOMMIT TRANSACTION;\n"


def aggregate(run_date):
    """Create tables if needed, run the day's transaction, then export the results as CSV."""
    bq.run_script((SQL_DIR / "00_ops_tables.sql").read_text(), run_date)
    try:
        bq.run_script(day_script(), run_date)
    except RuntimeError as e:
        if "OPS_BI_BLOCKED" in str(e):
            reason = str(e).split("OPS_BI_BLOCKED", 1)[1].strip().splitlines()[0].split(" at [")[0]
            raise Blocked(reason) from None
        raise
    run_dir = RUNS_DIR / str(run_date)
    run_dir.mkdir(parents=True, exist_ok=True)
    for name, query in EXPORTS.items():
        (run_dir / name).write_text(bq.query_csv(query, run_date))
    return run_dir


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", type=dt.date.fromisoformat)
    ap.add_argument("--skip-ai", action="store_true")
    args = ap.parse_args(argv)

    run_date = args.date or next_run_date()
    if run_date is None:
        print("Replay finished: all days up to", REPLAY_END, "are loaded.")
        return 0

    try:
        run_dir = aggregate(run_date)
    except Blocked as e:
        # The failed run (and GitHub's failure email) is the alert. The same date is retried next run.
        print(f"[{run_date}] BLOCKED, nothing loaded or published: {e}")
        return 1
    print(f"[{run_date}] aggregated -> {run_dir.relative_to(ROOT)}")

    from pipeline import ai_summary, render_dashboard
    if args.skip_ai:
        commentary = {"ok": False, "reason": "AI 요약을 건너뛰었어요 (--skip-ai)."}
    else:
        commentary = ai_summary.summarize(run_dir)
    (run_dir / "commentary.json").write_text(json.dumps(commentary, ensure_ascii=False, indent=2))
    print(f"[{run_date}] summary ok={commentary['ok']}")

    page = render_dashboard.render(run_dir)
    print(f"[{run_date}] dashboard -> {page.relative_to(ROOT)}")

    from pipeline import export_pdf
    pdf = export_pdf.export([str(run_date)])[0]
    print(f"[{run_date}] pdf -> {pdf.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
