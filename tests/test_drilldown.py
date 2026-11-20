import math
import unittest

from pipeline import ai_summary, drilldown as dd


def day(sessions, order_sessions, orders, orders_with_revenue, revenue, view=None, checkout=None):
    return {"sessions": sessions, "order_sessions": order_sessions, "orders": orders,
            "orders_with_revenue": orders_with_revenue, "revenue": revenue,
            "view_item_sessions": view if view is not None else sessions // 4,
            "checkout_sessions": checkout if checkout is not None else order_sessions * 3}


def seg(dim, val, w, sessions, order_sessions, days=7):
    return {"dim": dim, "val": val, "w": w, "days": str(days), "sessions": str(sessions),
            "order_sessions": str(order_sessions)}


PREV = [day(1000, 10, 11, 10, 700, view=250, checkout=40)] * 7
CUR = [day(1000, 15, 16, 14, 1100, view=250, checkout=60)] * 7  # CVR moves most; checkout step moves most
SEGMENTS = [seg("기기", "desktop", "prev", 4200, 42), seg("기기", "desktop", "cur", 4200, 63),
            seg("기기", "mobile", "prev", 2800, 28), seg("기기", "mobile", "cur", 2800, 42)]


class DecompositionTest(unittest.TestCase):
    def test_five_factors_multiply_to_revenue_but_three_do_not(self):
        sums = dd.window_sums(CUR)
        self.assertAlmostEqual(math.prod(calc(sums) for _, calc, _ in dd.FACTORS), sums["revenue"])
        three = math.prod(calc(sums) for _, calc, main in dd.FACTORS if main)
        self.assertNotAlmostEqual(three, sums["revenue"], places=0)

    def test_segment_effects_add_up_to_total_change(self):
        e = dd.segment_effects(SEGMENTS, "기기")
        total = 105 / 7000 - 70 / 7000
        self.assertAlmostEqual(e["mix"] + e["rate"] + e["inter"], total)
        self.assertAlmostEqual(e["mix"], 0)

    def test_segment_skipped_when_a_window_is_incomplete(self):
        rows = SEGMENTS[:-1] + [seg("기기", "mobile", "cur", 2800, 42, days=6)]
        self.assertIsNone(dd.segment_effects(rows, "기기"))


def texts(lines):
    return [l["text"] for l in lines]


class WhereLinesTest(unittest.TestCase):
    def test_walks_down_to_passed_term_step_and_segment(self):
        lines, segments = dd.where_lines(CUR, PREV, SEGMENTS)
        t = texts(lines)
        self.assertIn("판정 기준을 넘은 항: 세션 전환율.", t[0])
        self.assertIn("기준을 넘은 퍼널 단계: 체크아웃 진입률", t[1])
        self.assertTrue(any(l.startswith("기기:") for l in t))
        self.assertEqual(segments[0]["dim"], "기기")

    def test_every_passed_term_is_named(self):
        # Like 12/07: CVR and AOV both past their thresholds. AOV moves more but has no
        # children, so the segments go under CVR.
        cur = [day(1000, 15, 16, 14, 400, view=250, checkout=60)] * 7  # AOV 70 -> 29 (-59%), CVR +50%
        t = texts(dd.where_lines(cur, PREV, SEGMENTS)[0])
        self.assertIn("판정 기준을 넘은 항: 객단가, 세션 전환율.", t[0])
        self.assertTrue(t[1].startswith("객단가"))
        self.assertTrue(t[2].startswith("세션 전환율"))
        self.assertTrue(t[3].startswith("기기:"))

    def test_funnel_steps_named_when_cvr_is_within_threshold(self):
        # Like 12/13: view rate falls, checkout rate rises, CVR stays the same.
        cur = [day(1000, 10, 11, 10, 700, view=150, checkout=40)] * 7
        t = texts(dd.where_lines(cur, PREV, SEGMENTS)[0])
        self.assertIn("판정 기준을 넘은 항 없음.", t[0])
        self.assertTrue(any("기준 안쪽" in l and "상품 조회율" in l and "체크아웃 진입률" in l for l in t), t)
        self.assertFalse(any(l["muted"] for l in dd.where_lines(cur, PREV, SEGMENTS)[0]))

    def test_nothing_passed_shows_one_muted_reference(self):
        cur = [day(1050, 10, 11, 10, 720, view=262, checkout=42)] * 7
        lines = dd.where_lines(cur, PREV, SEGMENTS)[0]
        self.assertEqual(len(lines), 2)
        self.assertIn("판정 기준을 넘은 항 없음.", lines[0]["text"])
        self.assertTrue(lines[1]["muted"])
        self.assertTrue(lines[1]["text"].startswith("참고:"))

    def test_lines_state_facts_only(self):
        lines, _ = dd.where_lines(CUR, PREV, SEGMENTS)
        for line in texts(lines):
            self.assertFalse([w for w in ai_summary.CAUSAL_WORDS if w in line], line)

    def test_no_lines_when_a_window_has_no_orders(self):
        self.assertEqual(dd.where_lines([day(1000, 0, 0, 0, 0)] * 7, PREV, SEGMENTS), ([], []))

    def test_zero_change_has_no_minus_sign(self):
        self.assertEqual(dd._pp(-0.00001), "+0.00%p")


class TodayItemsTest(unittest.TestCase):
    def test_only_notable_headline_metrics(self):
        rows = [{"tier": "1", "flag": "notable", "metric_name": "매출", "unit": "count", "flag_change": "-0.3",
                 "flag_basis": "r7_wow"},
                {"tier": "1", "flag": "normal", "metric_name": "세션", "unit": "count", "flag_change": "0.1",
                 "flag_basis": "day_wow"},
                {"tier": "2", "flag": "notable", "metric_name": "장바구니율", "unit": "rate", "flag_change": "5",
                 "flag_basis": "r7_wow"}]
        items = dd.today_items(rows)
        self.assertEqual([i["name"] for i in items], ["매출"])
        self.assertFalse(items[0]["up"])


if __name__ == "__main__":
    unittest.main()
