import re
import unittest

from pipeline import render_dashboard as rd
from pipeline import run_daily


class DayScriptTest(unittest.TestCase):
    def test_one_transaction_with_the_gate_inside(self):
        s = run_daily.day_script()
        self.assertTrue(s.startswith("BEGIN TRANSACTION;"))
        self.assertTrue(s.rstrip().endswith("COMMIT TRANSACTION;"))
        self.assertEqual(s.count("BEGIN TRANSACTION"), 1)
        self.assertEqual(s.count("COMMIT TRANSACTION"), 1)
        self.assertLess(s.index("OPS_BI_BLOCKED"), s.index("COMMIT TRANSACTION"))

    def test_no_table_creation_inside_the_transaction(self):
        # BigQuery rejects CREATE TABLE inside a transaction; it lives in 00_ops_tables.sql.
        self.assertNotRegex(run_daily.day_script(), re.compile(r"^\s*CREATE TABLE", re.M))

    def test_gate_blocks_r_checks_and_arrival(self):
        sql = (run_daily.SQL_DIR / "05_ops_dq_results.sql").read_text()
        gate = sql[sql.index("IF EXISTS"):]
        self.assertIn("check_id LIKE 'R%'", gate)
        self.assertIn("check_id = 'DQ01_arrival'", gate)
        self.assertNotIn("DQ03", gate)


class NeedsCheckTest(unittest.TestCase):
    def row(self, check_id, status):
        return {"check_id": check_id, "status": status}

    def test_fail_on_r_arrival_or_missing_revenue(self):
        for check in ["R4_tid_split", "DQ01_arrival", "DQ03_null_revenue", "DQ07_order_revenue_gap"]:
            self.assertEqual(len(rd.needs_check([self.row(check, "FAIL")])), 1, check)

    def test_warnings_and_other_checks_stay_on_quality_tab(self):
        rows = [self.row("DQ03_null_revenue", "WARN"), self.row("DQ04_dup_orders", "WARN"),
                self.row("DQ08_funnel_tracking", "WARN"), self.row("R6_revenue_decomposition", "SKIP")]
        self.assertEqual(rd.needs_check(rows), [])


if __name__ == "__main__":
    unittest.main()
