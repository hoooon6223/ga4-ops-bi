import math
import unittest

from pipeline import render_dashboard as rd


def day(sessions, order_sessions, orders, orders_with_revenue, revenue):
    return {"sessions": sessions, "order_sessions": order_sessions, "orders": orders,
            "orders_with_revenue": orders_with_revenue, "revenue": revenue}


class DecomposeTest(unittest.TestCase):
    def test_product_equals_revenue_and_shares_add_up(self):
        # Several orders per session and orders without revenue: the 3-term formula is off here.
        prev = [day(1000, 10, 11, 10, 700)] * 7
        cur = [day(1100, 14, 16, 15, 1200)] * 7
        rows = rd.decompose(cur, prev)
        sums = rd.window_sums(cur)
        product = math.prod(calc(sums) for _, calc, _ in rd.FACTORS)
        self.assertAlmostEqual(product, sums["revenue"])
        three_terms = sums["sessions"] * (sums["order_sessions"] / sums["sessions"]) * (sums["revenue"] / sums["orders_with_revenue"])
        self.assertNotAlmostEqual(three_terms, sums["revenue"], places=0)
        shares = [float(r["share"].rstrip("%")) for r in rows[:-1]]
        self.assertAlmostEqual(sum(shares), 100, delta=len(shares))  # rounded to whole %
        self.assertEqual(rows[-1]["change"], f"{1200 / 700 - 1:+.1%}")

    def test_empty_window_returns_nothing(self):
        self.assertEqual(rd.decompose([day(1000, 0, 0, 0, 0)] * 7, [day(1000, 10, 11, 10, 700)] * 7), [])


if __name__ == "__main__":
    unittest.main()
