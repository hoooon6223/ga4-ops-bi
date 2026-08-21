# Issue Case Summary

## Selected Case

Use **January 2021 CVR drop** as the dashboard diagnosis case.

The GA4 sample covers:
- 2020-11-01 to 2021-01-31
- 92 complete daily rows

## Monthly KPI Profile

| Month | Sessions | Users | Purchasers | Orders | Revenue | Session CVR | AOV |
|---|---:|---:|---:|---:|---:|---:|---:|
| 2020-11 | 108,401 | 79,421 | 1,532 | 2,054 | 144,260 | 1.49% | 70.23 |
| 2020-12 | 133,368 | 104,315 | 1,975 | 2,434 | 160,555 | 1.59% | 65.96 |
| 2021-01 | 118,380 | 94,790 | 1,069 | 1,204 | 57,350 | 0.94% | 47.63 |

## Why This Works

December to January change:
- Sessions decreased, but not enough to explain the full revenue drop.
- Session CVR dropped sharply from 1.59% to 0.94%.
- AOV also decreased from 65.96 to 47.63.

Dashboard story:

> Revenue dropped in January. The KPI decomposition shows that the issue was not only traffic volume; conversion efficiency dropped materially, and AOV also weakened. The dashboard should first identify the CVR drop, then diagnose which funnel step and segment drove the decline.

## Dashboard Diagnosis Flow

1. Executive Monitoring
   - Detect January revenue and CVR decline.

2. KPI Decomposition
   - Compare Sessions, CVR, and AOV.

3. Funnel Diagnosis
   - Find whether the drop is concentrated in View Item, Add to Cart, Checkout, or Purchase.

4. Segment Drill-down
   - Check Device, Channel, Source/Medium, and New/Returning user.

5. Action
   - Convert the strongest segment/funnel finding into operational checks.

