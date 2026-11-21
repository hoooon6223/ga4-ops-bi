"""Re-write the AI comment for days that are already loaded, then re-render those days.

Numbers are not touched: the comment is made from each day's saved kpi_comparison.csv,
the same way the daily run does it. No BigQuery.

Usage: python -m pipeline.regen_comments 2020-11-01 2020-11-24
"""

import datetime as dt
import json
import sys

from pipeline import ai_summary, export_pdf, render_dashboard
from pipeline.run_daily import RUNS_DIR


def main(argv=None):
    start, end = (dt.date.fromisoformat(a) for a in (argv or sys.argv[1:]))
    days, failed = [], []
    d = start
    while d <= end:
        run_dir = RUNS_DIR / str(d)
        if run_dir.exists():
            c = ai_summary.summarize(run_dir)
            (run_dir / "commentary.json").write_text(json.dumps(c, ensure_ascii=False, indent=2))
            print(f"[{d}] summary ok={c['ok']}" + ("" if c["ok"] else f" ({c['reason']})"))
            days.append(str(d))
            if not c["ok"]:
                failed.append(str(d))
        d += dt.timedelta(days=1)
    for day in days:
        render_dashboard.render(RUNS_DIR / day)
    export_pdf.export(days)
    print(f"done: {len(days)} days, comment failed on {failed or 'none'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
