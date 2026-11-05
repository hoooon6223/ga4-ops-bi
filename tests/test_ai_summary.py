import unittest

from pipeline import ai_summary, fmt

COMPARISON = [
    {"metric_id": "K01_revenue", "unit": "count", "value_day": "1714.0", "r7_value": "", "r7_change": "-0.32",
     "wow_day_change": "", "dod_change": "", "mom_change": "", "mtd_value": ""},
    {"metric_id": "K05_session_cvr", "unit": "rate", "value_day": "0.0108", "r7_value": "", "r7_change": "0.15",
     "wow_day_change": "", "dod_change": "", "mom_change": "", "mtd_value": ""},
]
DQ = [{"check_id": "DQ03_null_revenue", "value": "0.0645", "status": "PASS"},
      {"check_id": "DQ08_funnel_tracking", "value": "0.0", "status": "WARN"}]
TABLE = fmt.placeholder_table(COMPARISON, DQ)
IDS = {"K01_revenue", "K05_session_cvr"}


def comment(text, metric_id="K01_revenue"):
    return {"headline": text, "highlights": [{"metric_id": metric_id, "direction": "down", "text": "매출 하락"}],
            "watch_items": [], "data_quality_note": "정상이에요."}


class ValidateTest(unittest.TestCase):
    def test_good_placeholder_passes(self):
        self.assertEqual(ai_summary.validate(comment("최근 7일 매출이 {{K01_revenue.r7_change}} 변했어요."), TABLE, IDS), [])

    def test_bare_number_fails(self):
        self.assertTrue(ai_summary.validate(comment("매출이 32% 줄었어요."), TABLE, IDS))

    def test_unknown_or_empty_placeholder_fails(self):
        self.assertTrue(ai_summary.validate(comment("{{K01_revenue.mom_change}}"), TABLE, IDS))  # empty value
        self.assertTrue(ai_summary.validate(comment("{{K99_fake.r7_change}}"), TABLE, IDS))

    def test_unknown_metric_fails(self):
        self.assertTrue(ai_summary.validate(comment("정상이에요.", metric_id="K99_fake"), TABLE, IDS))

    def test_fill_formats_by_unit(self):
        filled = fmt.fill("{{K01_revenue.r7_change}} / {{K05_session_cvr.r7_change}} / {{K01_revenue.value_day}}", TABLE)
        self.assertEqual(filled, "-32.0% / +0.15%p / $1,714")

    def test_status(self):
        self.assertEqual(ai_summary.status_of(DQ), "caution")
        self.assertEqual(ai_summary.status_of(DQ + [{"status": "FAIL"}]), "hold")


if __name__ == "__main__":
    unittest.main()
