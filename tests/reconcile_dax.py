"""
Post-deployment reconciliation test
===================================
Runs a DAX query against the PUBLISHED semantic model (Power BI REST API
'Datasets - Execute Queries') and compares every certified KPI with the independent
pandas reference in tests/kpi_reference_values.json. Fails the pipeline if any KPI
deviates by more than the tolerance -> a model is only promoted / endorsed as
"Certified" when its numbers are proven.

Env vars: TENANT_ID, CLIENT_ID, CLIENT_SECRET (service principal), WORKSPACE_ID, DATASET_ID
Usage:    python tests/reconcile_dax.py
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import msal
import requests

TOLERANCE = 0.001  # 0.1 %
REF = json.loads((Path(__file__).parent / "kpi_reference_values.json").read_text(encoding="utf-8"))

DAX = """
EVALUATE
SUMMARIZECOLUMNS (
    'Date'[Year],
    "work_orders",        [Work Orders],
    "total_cost_eur",     [Maintenance Cost],
    "downtime_cost_eur",  [Downtime Cost],
    "mttr_hours",         [MTTR (h)],
    "mtbf_hours",         [MTBF (h)],
    "availability_pct",   [Availability %] * 100,
    "pm_ratio_pct",       [PM Ratio %] * 100,
    "sla_compliance_pct", [SLA Compliance %] * 100,
    "first_time_fix_pct", [First Time Fix %] * 100
)
"""
YEAR_TO_PERIOD = {2024: "FY2024", 2025: "FY2025", 2026: "YTD2026"}


def token() -> str:
    app = msal.ConfidentialClientApplication(
        os.environ["CLIENT_ID"],
        authority=f"https://login.microsoftonline.com/{os.environ['TENANT_ID']}",
        client_credential=os.environ["CLIENT_SECRET"],
    )
    result = app.acquire_token_for_client(scopes=["https://analysis.windows.net/powerbi/api/.default"])
    return result["access_token"]


def run_dax() -> list[dict]:
    url = (f"https://api.powerbi.com/v1.0/myorg/groups/{os.environ['WORKSPACE_ID']}"
           f"/datasets/{os.environ['DATASET_ID']}/executeQueries")
    body = {"queries": [{"query": DAX}], "serializerSettings": {"includeNulls": True}}
    r = requests.post(url, json=body, headers={"Authorization": f"Bearer {token()}"}, timeout=120)
    r.raise_for_status()
    return r.json()["results"][0]["tables"][0]["rows"]


def main() -> int:
    failures = 0
    for row in run_dax():
        clean = {k.split("[")[-1].rstrip("]"): v for k, v in row.items()}
        period = YEAR_TO_PERIOD.get(int(clean["Year"]))
        if not period:
            continue
        expected = REF["portfolio"][period]
        for kpi, exp in expected.items():
            if kpi not in clean or exp is None:
                continue
            got = clean[kpi]
            dev = abs(got - exp) / abs(exp) if exp else abs(got)
            ok = dev <= TOLERANCE
            failures += not ok
            print(f"{'PASS' if ok else 'FAIL'}  {period:<8} {kpi:<20} expected {exp:>16,.3f}  got {got:>16,.3f}")
    print(f"\n{failures} failing KPI(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
