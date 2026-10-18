# 05 · Requirements workshop kit (consulting the specialist departments)

Use this 90-minute format whenever a department asks for "a dashboard". The output is a one-page **Report Canvas** that both sides sign before anything is built.

---

## Agenda (90 min)

| Time | Block | Key question | Technique |
|---|---|---|---|
| 0–10 | Context | Who will use this, how often, on which device? | Personas (max. 3) |
| 10–30 | **Decisions** | *Which decisions will you make differently with this report?* | "If the number goes up, what do you do?" |
| 30–50 | Questions & KPIs | Which questions support those decisions? Which KPI answers each? | Map to the KPI catalogue first — reuse before you invent |
| 50–65 | Data & gaps | Where does the data live? Who owns it? How fresh must it be? | Source-to-KPI matrix |
| 65–80 | Sketch | What should the first screen show? | Paper / whiteboard sketch, 5 numbers max. |
| 80–90 | Agreement | Scope of v1, success criteria, UAT testers, next demo date | Report Canvas sign-off |

## Report Canvas (template)

| Field | Answer |
|---|---|
| Report name & audience | |
| Decisions supported (max. 3) | |
| Key questions → KPI (from catalogue or **new**) | |
| New KPI definitions needed (owner, formula, example) | |
| Data sources & owners | |
| Freshness requirement (daily / hourly / real-time) | |
| Security: who may see which rows? | |
| Success criteria after 90 days | e.g. "weekly ops meeting uses only this report" |
| Out of scope for v1 | |
| UAT testers / sign-off by | |

## Example: Field Service (filled in)

| Field | Answer |
|---|---|
| Decisions | (1) Re-assign technicians between sites weekly · (2) Escalate P1 backlog older than 4 h · (3) Plan junior training |
| Questions → KPI | Are we meeting SLA? → `SLA Compliance %` · Is the backlog growing? → `Open Backlog` (ageing buckets) · Who needs coaching? → `First Time Fix %` by skill level |
| New KPI | *Repeat visit rate* (owner: Head of Field Service) — added to the catalogue after board approval |
| Freshness | Hourly for backlog (DirectQuery page), daily for the rest |
| Security | Regional leads see their region only → `Regional Reader` role |
| Success | Weekly dispatch meeting runs from the report; P1 SLA ≥ 95 % within 3 months |

## Questions that save weeks later

* "What do you do *today* to get this number? Show me the Excel." (→ hidden business rules)
* "If two reports show different values for this KPI, which one is right?" (→ data owner)
* "Who must **not** see this?" (→ RLS early, not after go-live)
* "What happens if the report is not available for a day?" (→ refresh SLA, support tier)
