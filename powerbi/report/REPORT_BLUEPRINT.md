# Report blueprint · "ATLAS Maintenance Performance"

Canvas 1280 × 720 · theme `atlas_theme.json` · audience: Management, Asset Management, Field Service, Controlling.
Every page answers **one question**, shows **5 or fewer key numbers**, and offers one obvious next click.

---

## Design standards (apply to every page)

| Standard | Rule |
|---|---|
| Layout grid | 24 px outer margin, 16 px gutter. Header band 64 px: page title (`[Dynamic Page Title]`), data freshness (`[Data Freshness]`), slicer pane button. |
| Reading order | Z-pattern: KPIs top-left → trend → breakdown → detail. Tab order set explicitly (View → Selection pane) for keyboard users. |
| Colour | Brand blue for data, orange **only** for the highlighted/negative item, red/amber/green **only** via `[Budget Status Color]`. Never colour as the only signal: icons ▲▼ and labels too. |
| Numbers | Cards show the value + vs PY + vs budget. Units in titles ("Cost (€)"), not in every label. |
| Slicers | Sync slicers for Year, Region, Asset Type across pages; collapsed in a slicer pane (bookmark toggle) to keep the canvas clean. |
| Accessibility | Alt text on every visual (dynamic alt text with measures), minimum contrast 4.5:1, font ≥ 10 pt, no information in tooltips only. |
| Performance | ≤ 12 visuals per page, Performance Analyzer target: every visual < 500 ms DAX. |

---

## Page 1 · Executive Overview — *"Are we on track?"*

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ Maintenance performance | All regions | 2026          Data as of 30.09.2026  │
├────────────┬────────────┬────────────┬────────────┬────────────┬─────────────┤
│ Maint. cost│ vs Budget  │ TCO        │Availability│ PM ratio   │ SLA         │
│ 6.53 M€    │ −x.x %     │ 22.1 M€    │ 99.52 %    │ 71 %       │ 96.2 %      │
│ ▼ vs PY    │ ●          │ ▲ vs PY    │ ▲ +0.0 pp  │ ▲ +x pp    │ ▼ −x pp     │
├────────────┴────────────┴──────────┬─┴────────────┴────────────┴─────────────┤
│ Cost vs budget by month (column +  │ Site map: bubble = cost, colour =        │
│ line, field parameter KPI switch)  │ [Budget Status Color]                    │
├────────────────────────────────────┼──────────────────────────────────────────┤
│ [Executive Narrative] (smart text) │ Site scorecard: variance %, availability,│
│                                    │ SLA, PM ratio with icons, drill-through  │
└────────────────────────────────────┴──────────────────────────────────────────┘
```

* KPI cards use the *Time Intelligence* calc group (`YoY Δ`) as reference label.
* The trend chart's Y axis is the **KPI Selector** field parameter → users pick the KPI themselves.
* Scorecard rows → **drill-through** to *Site Detail*.

## Page 2 · Reliability & Assets — *"Which assets hurt us, and should we repair or replace?"*

* Line: `[MTBF (h)]` and `[MTTR (h)]` by month, split by Asset Type (small multiples).
* Pareto: columns `[Downtime Hours]` by Failure Description + line `[Downtime Pareto Cumulative %]`, 80 % constant line.
* Scatter "risk matrix": X = `[Failure Work Orders]`, Y = `[Total Cost of Ownership]`, size = `[Downtime Hours]`, legend = Criticality, play axis = Year Month.
* Table "Repair or replace": Asset, Site, Age, Criticality, `[Asset Risk Score]`, `[Cost to Replacement Ratio]` with data bars, Top N = 15 by risk score. Conditional icon: ≥ 1.0 "Replace".

## Page 3 · Service Performance — *"Do we respond fast enough and fix it the first time?"*

* `[SLA Compliance %]` by Priority × Region matrix with background colour scale.
* `[First Time Fix %]` by Skill Level (bar) → coaching insight: Junior FTF is ~13 pp below Senior.
* Backlog ageing: stacked bar 0–7 / 8–30 / 30+ days by Region (`[Open Backlog]`).
* Decomposition tree: `[Avg Response (h)]` → Region → Site → Priority → Technician (AI split enabled).

## Page 4 · Budget & Finance — *"Where does the money go and where will we land?"*

* Waterfall: budget → variance by site → actual.
* `[Maintenance Cost Forecast FY]` vs annual budget, bullet chart per site.
* Cost structure: labour vs material vs downtime (100 % stacked).
* What-if parameter "PM shift %": simulates moving x % of corrective work orders to preventive using the observed cost difference.

## Page 5 · PM Programme Impact — *"Did the Süd preventive maintenance programme pay off?"*

* Before/after (12 months each side of 2025-07-01) for Treatment (Süd) vs Control (other regions): PM ratio, emergency share, cost per asset, TCO per asset, availability.
* Line chart with a vertical "go-live" marker (constant line on the date axis).
* Text box with the difference-in-differences result (validated in `sql/snowflake/06_analytical_queries.sql`, Q4).

## Page 6 · Platform Health *(governance cockpit, BI team only)*

* DQ test status from `ATLAS_GOVERNANCE.DQ.V_DQ_LATEST` (pass/fail, failing rows, owner).
* Refresh history & duration (Power BI REST API → `governance/scripts/tenant_inventory.py` output).
* Usage: views per report, active users per department, unused reports > 90 days (candidates for archiving).
* Access: grants expiring in the next 30 days (re-certification list).

## Supporting pages

* **Site Detail** (drill-through on Site): all KPIs for one site + its asset list and top failure modes.
* **Asset Detail** (drill-through on Asset): work-order history timeline, SCD2 attribute history (e.g. criticality changes), cost to date.
* **Tooltip page** "KPI definition": shows the measure description + owner for the hovered KPI — governance made visible.

## Interactions & navigation

* Page navigator (buttons) in the header; bookmarks for "Reset filters" and "Show slicer pane".
* Edit interactions: the narrative card is not cross-filtered by the scorecard (it always describes the page scope).
* Mobile layout for page 1 (managers on the road): 6 KPIs + narrative only.
