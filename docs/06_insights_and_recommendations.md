# 06 · Insights & recommendations (management summary)

*Data: 33,464 work orders, 943 assets, 12 sites, Jan 2024 – Sep 2026. All figures are reproducible with `scripts/kpi_reference.py` and reconcile with the certified Power BI measures and the SQL in `sql/snowflake/06_analytical_queries.sql`.*

> A dashboard is only worth its decisions. These are the four decisions this platform supports, with the evidence behind each.

---

## 1 · Roll out the preventive maintenance programme company-wide — **≈ €3.2 M p.a. TCO potential (conservative)**

The PM programme launched in region **Süd** on 1 July 2025. Comparing 12 months before vs. after, against the other regions as a control group (difference-in-differences):

| | Süd (programme) before → after | Other regions before → after |
|---|---|---|
| PM ratio | 69.9 % → **85.5 %** | 67.7 % → 66.9 % |
| Emergency share of failures | 21.6 % → **10.0 %** | 22.7 % → 21.0 % |
| Maintenance cost per asset | €8,953 → €8,259 (**−7.8 %**) | €9,253 → €9,169 (−0.9 %) |
| TCO per asset (incl. downtime) | €28,956 → €21,620 (**−25.3 %**) | €31,728 → €32,576 (+2.7 %) |
| Availability | 99.53 % → 99.72 % | 99.50 % → 99.50 % |

**Difference-in-differences on TCO per asset: −28 pp.** More preventive work did *not* increase maintenance spend — it reduced it, and it halved emergency call-outs.
Applying **half** of the observed effect to the 691 assets outside Süd ≈ **€3.2 M lower TCO per year** (full effect ≈ €6.3 M).
**Recommendation:** roll out region by region (West first, see §2), track with the *PM Programme Impact* page. *Caveat:* TCO uses Controlling's downtime rates (A €1,200/h, B €450/h, C €150/h); maintenance cost alone also falls (−7.8 % vs −0.9 %), so the direction holds without the downtime assumption.

## 2 · Replace 20 end-of-life pumps in Duisburg — **€0.74 M capex vs. €1.54 M annual TCO**

Duisburg Rhein is the only site that is getting worse on every dimension (YTD 2026 vs YTD 2025):

* Maintenance cost **€845 k, +13.3 % over budget** and +23.5 % vs. last year (company: 6.8 % *under* budget)
* Lowest availability of all sites (**99.31 %**), SLA compliance **87.7 %** (other sites 95–98 %)
* PM ratio *fell* from 64.5 % to 59.1 % — the crew is fire-fighting

Root cause: the pump fleet installed 1996–2005. **20 pumps** have a 12-month TCO (repairs + downtime) **higher than their replacement value** — together €1.54 M TCO vs. €0.74 M to replace. The worst, `PUMP-S05-0336` (criticality A, 26 years), caused €232 k TCO against a €35 k replacement value.
**Recommendation:** approve a replacement programme for the 20 pumps (payback < 6 months on TCO), then include Duisburg in the PM rollout. The *Repair or replace* table on the Reliability page keeps this list current.

## 3 · Target bearing and seal failures with condition monitoring

Bearing wear (17.5 %) and seal leakage (11.1 %) cause **28.6 % of all failure downtime** in 2026 — mostly pumps and compressors. Both are detectable weeks in advance with vibration and temperature sensors.
**Recommendation:** pilot vibration monitoring on criticality-A pumps/compressors in two sites; measure the effect with the same before/after method.

## 4 · Pair junior technicians with seniors — first-time fix gap of ~15 pp to seniors

First-time-fix rate on failure work orders (2026): Junior **70.6 %** · Professional 81.2 % · Senior 85.2 % · Expert 93.3 %.
Every failed first visit means a second call-out and longer downtime. Bringing juniors to professional level would have avoided ~65 repeat visits this year.
**Recommendation:** buddy system for juniors on criticality-A assets and a "top 5 failure modes" training built from the Pareto above.

---

## How the platform made these insights possible

* **One certified definition** of availability, MTBF, TCO… — no more "my Excel says something else" (KPI catalogue, `docs/07`).
* **Downtime cost as a KPI** makes preventive and reactive work comparable in euros — the key to decision 1.
* **SCD2 asset history** keeps old figures stable when assets are re-classified.
* **Self-service on certified data:** the Duisburg site manager built his own pump-fleet report on the certified model in one afternoon after the Level 2 training (`docs/03`).
