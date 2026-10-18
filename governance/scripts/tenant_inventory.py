"""
Tenant inventory & activity extraction for the Platform Health page
===================================================================
Runs daily (scheduled pipeline). Uses the Power BI Admin APIs (service principal with
"Allow service principals to use read-only admin APIs" enabled in tenant settings).

Writes CSVs (or loads them to ATLAS_GOVERNANCE.MONITORING in Snowflake):
  workspaces.csv, workspace_access.csv, datasets.csv, reports.csv, activity_<date>.csv,
  governance_findings.csv  <- the actionable list for the BI platform owner
"""
from __future__ import annotations

import datetime as dt
from pathlib import Path

import pandas as pd

from pbi_client import PowerBI

OUT = Path("out/inventory")
OUT.mkdir(parents=True, exist_ok=True)
pbi = PowerBI()

# ---------------------------------------------------------------- inventory (all workspaces, incl. users & content)
ws = pbi.get("/admin/groups", **{"$top": 5000, "$expand": "users,reports,datasets",
                                  "$filter": "type eq 'Workspace' and state eq 'Active'"})["value"]
workspaces = pd.DataFrame([{"workspace_id": w["id"], "workspace": w["name"],
                            "capacity_id": w.get("capacityId"), "is_on_capacity": w.get("isOnDedicatedCapacity")}
                           for w in ws])
access = pd.DataFrame([{"workspace": w["name"], "principal": u.get("identifier"),
                        "principal_type": u.get("principalType"), "role": u.get("groupUserAccessRight")}
                       for w in ws for u in w.get("users", [])])
datasets = pd.DataFrame([{"workspace": w["name"], "dataset_id": d["id"], "dataset": d["name"],
                          "endorsement": (d.get("endorsementDetails") or {}).get("endorsement", "None"),
                          "configured_by": d.get("configuredBy"), "sensitivity": (d.get("sensitivityLabel") or {}).get("labelId")}
                         for w in ws for d in w.get("datasets", [])])
reports = pd.DataFrame([{"workspace": w["name"], "report_id": r["id"], "report": r["name"],
                         "dataset_id": r.get("datasetId")} for w in ws for r in w.get("reports", [])])

# ---------------------------------------------------------------- activity log (yesterday, paged via continuation)
day = dt.date.today() - dt.timedelta(days=1)
events, page = [], pbi.get("/admin/activityevents",
                           startDateTime=f"'{day}T00:00:00.000Z'", endDateTime=f"'{day}T23:59:59.999Z'")
while True:
    events += page.get("activityEventEntities", [])
    if page.get("lastResultSet"):
        break
    page = pbi.s.get(page["continuationUri"], timeout=120).json()
activity = pd.DataFrame(events)

# ---------------------------------------------------------------- governance findings (rules = the standards in docs/02)
findings = []
for w in ws:
    name, users = w["name"], w.get("users", [])
    if not any(u.get("groupUserAccessRight") == "Admin" for u in users):
        findings.append((name, "ORPHANED_WORKSPACE", "No admin assigned"))
    persons = [u["identifier"] for u in users if u.get("principalType") == "User"
               and u.get("groupUserAccessRight") in ("Member", "Contributor", "Viewer")]
    if persons and name.endswith("-PROD"):
        findings.append((name, "INDIVIDUAL_ACCESS_IN_PROD", f"{len(persons)} users granted directly - use groups"))
    if name.endswith("-PROD") and not w.get("isOnDedicatedCapacity"):
        findings.append((name, "PROD_NOT_ON_CAPACITY", "Production workspace on shared capacity"))
    if not (name.startswith(("ATLAS-", "DEPT-", "SANDBOX-")) and name.split("-")[-1] in ("DEV", "TEST", "PROD")):
        findings.append((name, "NAMING_CONVENTION", "Workspace name violates <PROGRAM>-<Domain>-<STAGE>"))

if not activity.empty and "DatasetId" in activity:
    views = activity[activity.Activity == "ViewReport"].groupby("DatasetId").size()
    uncert = datasets[datasets.endorsement != "Certified"].set_index("dataset_id")
    for ds_id, n in views.items():
        if ds_id in uncert.index and n >= 50:
            findings.append((uncert.loc[ds_id, "workspace"], "HIGH_USE_UNCERTIFIED",
                             f"{uncert.loc[ds_id, 'dataset']}: {n} views/day - candidate for certification"))

for name, df in {"workspaces": workspaces, "workspace_access": access, "datasets": datasets,
                 "reports": reports, f"activity_{day}": activity,
                 "governance_findings": pd.DataFrame(findings, columns=["workspace", "rule", "detail"])}.items():
    df.to_csv(OUT / f"{name}.csv", index=False)
print(f"{len(ws)} workspaces, {len(datasets)} models, {len(events)} events, {len(findings)} findings")
