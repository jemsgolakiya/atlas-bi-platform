# 03 · Self-service BI enablement & coaching programme

> Self-service fails for two reasons: users get **no trusted data** (so they rebuild it in Excel) or they get **no support** (so they give up). ATLAS solves the first with certified semantic models and the second with this programme.

---

## 1 · Maturity path — "from consumer to champion"

| Level | Role | Can do | Training | Access granted after |
|---|---|---|---|---|
| **0 · Consumer** | Everyone | Use apps, filter, subscribe, export (where allowed), ask Copilot questions on certified models | 45-min onboarding video + "How to read our KPIs" one-pager | Automatic (app audience) |
| **1 · Explorer** | Interested users | *Analyze in Excel*, personal reports on certified models in *My workspace* | Workshop L1 (3 h) | Attendance |
| **2 · Report Author** | 1–2 per team | Departmental reports on certified models (live connection), publish to `DEPT-*` workspaces | Workshop L2 (2 × 4 h) + **graded mini-project** | Passing the project review → *Build* permission + Contributor in DEPT-DEV |
| **3 · Champion** | 1 per department | Composite models (add own Excel/SharePoint data), mentor colleagues, first-level support, nominate content for certification | L3 (DAX & modelling, 3 × 4 h) + community participation | Platform Owner nomination |

## 2 · Curriculum

**L1 – Explore (3 h)**
* Find data: OneLake data hub, endorsement badges, what *Certified* means
* Read the KPI catalogue; why "availability" has exactly one definition
* Build a report on `SM AssetMgmt Maintenance`: cards, matrix, slicers, drill-through
* Hands-on: "Which of *my* sites missed SLA last month?"

**L2 – Author (2 × 4 h)**
* Report design standards (the blueprint), accessibility, mobile layout
* Field parameters, bookmarks, tooltips, conditional formatting with `[Budget Status Color]`
* Publishing, apps and audiences, sharing rules — and what *not* to do (no "Share" of PROD reports to individuals)
* Quick measures & simple DAX (CALCULATE + filter), *why* most logic belongs in the certified model
* **Mini-project:** department-specific report, reviewed against a checklist (data source = certified model, standards, performance analyzer < 1 s, alt texts)

**L3 – Champion (3 × 4 h)**
* Star schema & relationships, filter context vs. row context, iterators, time intelligence, calculation groups
* Composite models & DirectQuery for Power BI datasets, RLS behaviour in composite models
* Performance tuning (Performance Analyzer, DAX Studio, VertiPaq Analyzer)
* Governance: certification process, requesting a new certified KPI, data owner role

## 3 · Support model

| Channel | For | Response |
|---|---|---|
| Teams community *"ATLAS BI Community"* | How-to questions, sharing reports, tips | Community + Champions, same day |
| **Office hours** (Tue & Thu 14:00–15:00) | 1:1 help on your report / DAX | BI team, live |
| Ticket (ServiceNow) | Access, bugs in certified content, new KPI requests | SLA: 2 business days |
| Monthly **"Show & Tell"** (30 min) | Departments demo what they built — the best adoption driver | — |
| Knowledge base (SharePoint) | Recorded trainings, cheat sheets, templates, the KPI catalogue | — |

## 4 · Consulting specialist departments: from request to report

1. **Discovery workshop (90 min)** with the department using `docs/05_requirements_workshop_kit.md`: decisions → questions → KPIs → data.
2. **Clickable mock-up within 1 week** (Power BI on sample data) — users react to something real instead of writing specifications.
3. **Build in iterations of 2 weeks** with a fixed demo slot; the department's Champion co-builds where possible (coaching on the job).
4. **UAT in TEST workspace** with real users and real data; sign-off by the Data Owner.
5. **Launch:** app audience, 30-min training for end users, adoption tracked for 90 days.
6. **Retro after 90 days:** usage, decisions made, what to change. Unused pages are removed.

## 5 · Measuring success of the programme

| KPI | Target year 1 |
|---|---|
| Share of report views on certified models | > 80 % |
| Active Report Authors / Champions | 25 / 8 (one per department) |
| Departmental reports built by departments themselves | > 50 % of new reports |
| Median time request → first mock-up | ≤ 5 business days |
| Training satisfaction (NPS) | > 40 |
| Excel "shadow reports" for the same KPI (survey) | −50 % |
