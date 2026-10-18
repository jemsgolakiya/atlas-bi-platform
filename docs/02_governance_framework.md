# 02 · Power BI governance framework (lifecycle & access control)

> Goal: **"Managed self-service."** Departments build freely *on top of* certified data; the platform team guarantees that what is certified is correct, secure and maintained. Governance should feel like a paved road, not a toll gate.

---

## 1 · Operating model & roles

| Role | Who | Accountable for |
|---|---|---|
| **BI Platform Owner** | Head of BI (this position) | Tenant settings, capacity, standards, roadmap, certification decisions |
| **Data Owner** | Head of each department (Asset Mgmt, Field Service, Controlling) | KPI definitions, access approvals for their data, quarterly access re-certification |
| **BI Engineer** | Central BI team | Snowflake GOLD, certified semantic models, CI/CD, performance |
| **Report Author (Champion)** | 1–2 trained power users per department | Departmental reports on certified models, first-level support, coaching colleagues |
| **Consumer** | Everyone else | Uses apps, subscribes, gives feedback |
| **Data Governance Board** | Platform owner + data owners, monthly 45 min | Approves new certified KPIs, resolves definition conflicts, reviews the health dashboard |

**RACI for the most frequent requests**

| Activity | Platform Owner | Data Owner | BI Engineer | Champion |
|---|---|---|---|---|
| New KPI in certified model | A | R (definition) | R (build) | C |
| New departmental report | I | A | C | R |
| Access to a region's data | I | A (approve) | R (entitlement) | – |
| Promote content to PROD | A | C (UAT sign-off) | R | – |
| Endorse as *Certified* | A/R | C | C | – |

---

## 2 · Content tiers — "who may build what, where"

| Tier | Content | Built by | Where | Endorsement | Support |
|---|---|---|---|---|---|
| **1 · Enterprise** | Certified semantic models + core reports (this repo) | BI team | `ATLAS-[Domain]-PROD` via deployment pipeline | **Certified** | BI team, SLA |
| **2 · Departmental** | Reports & small models built **on Tier 1 models** (live connection / composite) | Champions | `DEPT-[Department]-PROD` (own pipeline, lighter checks) | **Promoted** | Champion, BI team on request |
| **3 · Personal** | Exploration, prototypes | Anyone with a Pro licence | *My workspace* / `SANDBOX-[Department]` | none | none, auto-archived after 90 days of no use |

**Promotion path:** a Tier 3 prototype that gets ≥ 20 regular users is *nominated* to Tier 2; a Tier 2 report that becomes business-critical or reused across departments is rebuilt in Tier 1. Usage data from the activity log drives these decisions — not opinions.

---

## 3 · Workspace strategy & naming conventions

```
ATLAS-AssetMgmt-DEV   ──►  ATLAS-AssetMgmt-TEST   ──►  ATLAS-AssetMgmt-PROD   ──►  App "Asset Management"
 (Git-integrated)          (UAT with department)        (certified, read-only)       (audience groups)
```

| Object | Convention | Example |
|---|---|---|
| Workspace | `<PROGRAM>-<Domain>-<STAGE>` | `ATLAS-Finance-PROD` |
| Semantic model | `SM <Domain> <Subject>` | `SM AssetMgmt Maintenance` |
| Report | `<Subject> – <Audience>` | `Maintenance Performance – Management` |
| Dataflow | `DF <Source> <Entity>` | `DF CMMS WorkOrders` |
| Entra ID groups | `sg-pbi-<workspace>-<role>` | `sg-pbi-atlas-assetmgmt-prod-viewer` |
| Measures | Business language, unit in name if ambiguous | `MTTR (h)`, `Availability %` |

---

## 4 · Lifecycle management (ALM)

**Source control.** All Tier 1 content is saved as **Power BI Project (.pbip) with TMDL** in Git. Every change is a pull request: diffable measures, reviewable relationships, rollback = `git revert`.

**Branching.** `feature/*` → PR → `main`. `main` is synced to the DEV workspace through Fabric Git integration.

**Automated quality gates** (`.github/workflows/powerbi-ci.yml`)

| Gate | Tool | Blocks merge when |
|---|---|---|
| Measure catalogue in sync | `generate_measure_artifacts.py` + `git diff --exit-code` | YAML, TMDL, DAX and KPI catalogue differ |
| Best Practice Analyzer | Tabular Editor 2 CLI + `governance/bpa/BPARules.json` | any rule with severity 3 fails |
| DAX & M formatting | DAX formatter / lint | – (warning) |
| Data quality | `CALL SP_RUN_DQ_TESTS()` in Snowflake TEST | any ERROR test fails |
| **KPI reconciliation** | `tests/reconcile_dax.py` against the TEST model | any KPI deviates > 0.1 % from the SQL/pandas reference |
| UAT sign-off | GitHub environment approval by the Data Owner | no approval |

**Deployment.** Power BI deployment pipeline DEV → TEST → PROD, triggered by the workflow through the REST API, with **deployment rules** that switch the `Environment` parameter (DEV/TEST/PROD → Snowflake database). The same artefact moves through all stages — nothing is edited in PROD.

**Versioning & release notes.** Semantic version per model (`1.4.0`), stored in the model description; release notes are generated from merged PR titles and published in the app's "What's new" page.

**Retirement.** Reports with zero views in 90 days → owner notified → archived after 30 more days → deleted after 180 days (export kept in Git).

---

## 5 · Access control model

**Principles:** least privilege · groups not people · access expires · every grant has a ticket · data security in the data, not in the report.

| Layer | Mechanism | Who decides |
|---|---|---|
| Tenant | Tenant settings restricted to security groups (e.g. *Publish to web* = disabled, *Export to Excel* = certified-model consumers only, *Create workspaces* = `sg-pbi-workspace-creators`) | Platform Owner |
| Workspace | Admin = BI team only · Member = BI engineers · Contributor = Champions (DEV/TEST only) · Viewer = not used — consumers get **apps** | Platform Owner |
| App audience | Audiences per department mapped to Entra ID groups | Data Owner |
| Semantic model | **RLS** role `Regional Reader` (region via Security Bridge) · **OLS** hides `Email`, `Hourly Rate` · *Build* permission only for Champions | Data Owner |
| Data platform | Snowflake row access + masking policies driven by the **same** entitlement table | Data Owner |
| Information protection | Sensitivity labels (Microsoft Purview) inherited downstream: `Internal` default, `Confidential` for Finance models; export blocked for `Strictly confidential` | Platform Owner / InfoSec |

**Access request flow** (Power Automate, see `docs/04_power_platform.md`):
request form → Data Owner approval → entitlement row written with ticket ID and expiry → group membership updated → requester notified. **Quarterly re-certification:** each Data Owner receives the list of people with access to their data and confirms or revokes with one click; un-confirmed grants expire automatically.

**Testing security:** "View as role" checks are part of UAT; CI runs the Snowflake verification queries in `04_security_policies.sql`; RLS test users per region exist in TEST.

---

## 6 · Certification checklist (Tier 1)

- [ ] All BPA severity-3 rules pass; ≤ 5 severity-2 warnings with documented exceptions
- [ ] Every visible measure has a description, folder and format (KPI catalogue generated)
- [ ] KPI reconciliation passes against SQL reference
- [ ] RLS/OLS tested with test accounts for each role
- [ ] Incremental refresh configured; full refresh < 15 min; largest visual < 500 ms
- [ ] Data owner named, support contact in model description, sensitivity label set
- [ ] Endorsed **Certified** by the Platform Owner, listed in the OneLake data hub with documentation link

---

## 7 · Monitoring & capacity

* **Tenant inventory + activity log** extracted daily (`governance/scripts/tenant_inventory.py`) → *Platform Health* page: orphaned workspaces, workspaces with individual users instead of groups, uncertified models with high usage, failing refreshes, top/unused reports.
* **Fabric Capacity Metrics app** for CU consumption; alert at 80 % sustained utilisation; heavy refreshes scheduled outside 07:00–10:00.
* **Snowflake** cost view `MONITORING.V_BI_QUERY_COST` + resource monitor on the ad-hoc warehouse.
* **KPIs for the platform itself** (reported to the Governance Board monthly): % of report views on certified content (target > 80 %), refresh success rate (> 99 %), median time from request to delivery, number of active Champions, adoption per department.
