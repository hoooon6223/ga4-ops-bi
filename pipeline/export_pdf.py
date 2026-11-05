"""Save each day's dashboard as a PDF (site/pdf/<date>.pdf) next to its HTML page.

The print layout (templates/_style.html, @media print) expands all three report pages.

Usage:
  python -m pipeline.export_pdf             # every day that has an HTML page but no PDF
  python -m pipeline.export_pdf 2020-11-28  # specific days (overwrites)
"""

import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
DAYS = ROOT / "site" / "days"
PDF = ROOT / "site" / "pdf"


def export(days):
    PDF.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(viewport={"width": 1200, "height": 900})
        page.emulate_media(media="print", color_scheme="light")
        for day in days:
            page.goto((DAYS / f"{day}.html").as_uri())
            page.pdf(path=PDF / f"{day}.pdf", format="A4", landscape=True, print_background=True, scale=0.7,
                     margin={"top": "10mm", "bottom": "10mm", "left": "10mm", "right": "10mm"})
        browser.close()
    return [PDF / f"{d}.pdf" for d in days]


if __name__ == "__main__":
    days = sys.argv[1:] or sorted(p.stem for p in DAYS.glob("*.html") if not (PDF / f"{p.stem}.pdf").exists())
    for path in export(days):
        print(path.relative_to(ROOT))
