"""
Local GOLD layer builder
========================
Mirrors sql/snowflake/02_silver_cleansed.sql + 03_gold_star_schema.sql in pandas so the
Power BI model can be built WITHOUT a Snowflake account (Power Query parameter
DataSource = "LocalCSV"). Column names are identical to Snowflake GOLD, so switching
the parameter to "Snowflake" changes nothing in the model.

Usage: python scripts/build_gold.py   -> writes data/gold/*.csv
"""
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
D, G = ROOT / "data", ROOT / "data" / "gold"
G.mkdir(parents=True, exist_ok=True)

wo = pd.read_csv(D / "fact_work_order.csv", parse_dates=["created_ts", "started_ts", "completed_ts"])
asset = pd.read_csv(D / "dim_asset.csv", parse_dates=["valid_from"])
asset["valid_to"] = pd.to_datetime(asset.valid_to.replace("9999-12-31", "2262-04-11"))
site = pd.read_csv(D / "dim_site.csv")
tech = pd.read_csv(D / "dim_technician.csv")
fc = pd.read_csv(D / "dim_failure_code.csv")
budget = pd.read_csv(D / "fact_budget.csv", parse_dates=["month"])
date = pd.read_csv(D / "dim_date.csv")
RATE = {"A": 1200, "B": 450, "C": 150}
REF_YEAR = 2026

# ---- dimensions
dim_site = site.reset_index(names="SITE_KEY").assign(SITE_KEY=lambda x: x.SITE_KEY + 1)
dim_site.columns = [c.upper() for c in dim_site.columns]

dim_asset = asset.rename(columns={"asset_sk": "ASSET_KEY"})
dim_asset.columns = [c.upper() for c in dim_asset.columns]
dim_asset["ASSET_AGE_YEARS"] = REF_YEAR - dim_asset.INSTALL_YEAR
dim_asset["AGE_BAND"] = pd.cut(dim_asset.ASSET_AGE_YEARS, [-1, 9, 19, 200],
                               labels=["0-9 years", "10-19 years", "20+ years"]).astype(str)

dim_tech = tech.reset_index(names="TECHNICIAN_KEY").assign(TECHNICIAN_KEY=lambda x: x.TECHNICIAN_KEY + 1)
dim_tech.columns = [c.upper() for c in dim_tech.columns]
dim_tech = dim_tech.rename(columns={"REGION": "HOME_REGION"})
dim_tech = pd.concat([dim_tech, pd.DataFrame([{"TECHNICIAN_KEY": -1, "TECHNICIAN_ID": "UNKNOWN",
                                               "TECHNICIAN_NAME": "Unassigned", "HOME_REGION": "n/a",
                                               "SKILL_LEVEL": "n/a"}])])

dim_fc = fc.reset_index(names="FAILURE_KEY").assign(FAILURE_KEY=lambda x: x.FAILURE_KEY + 1)
dim_fc.columns = [c.upper() for c in dim_fc.columns]
dim_fc["IS_FAILURE"] = dim_fc.FAILURE_CODE != "F00"

dim_date = date.rename(columns=str.upper)

# ---- fact (silver rules + point-in-time SCD2 join)
f = wo[wo.technician_id.notna() & (wo.labor_hours > 0) & (wo.status != "Cancelled")].copy()
f = f.merge(asset[["asset_sk", "asset_id", "criticality", "valid_from", "valid_to"]], on="asset_id")
f = f[(f.created_ts.dt.normalize() >= f.valid_from) & (f.created_ts.dt.normalize() <= f.valid_to)]
f = f.merge(dim_site[["SITE_KEY", "SITE_ID"]], left_on="site_id", right_on="SITE_ID")
f = f.merge(dim_tech[["TECHNICIAN_KEY", "TECHNICIAN_ID"]], left_on="technician_id", right_on="TECHNICIAN_ID", how="left")
f = f.merge(dim_fc[["FAILURE_KEY", "FAILURE_CODE"]], left_on="failure_code", right_on="FAILURE_CODE")
fact = pd.DataFrame({
    "WORK_ORDER_ID": f.work_order_id,
    "CREATED_DATE_KEY": f.created_ts.dt.strftime("%Y%m%d").astype(int),
    "COMPLETED_DATE_KEY": f.completed_ts.dt.strftime("%Y%m%d"),
    "ASSET_KEY": f.asset_sk, "SITE_KEY": f.SITE_KEY, "TECHNICIAN_KEY": f.TECHNICIAN_KEY.fillna(-1).astype(int),
    "FAILURE_KEY": f.FAILURE_KEY, "WORK_ORDER_TYPE": f.work_order_type,
    "IS_FAILURE": f.work_order_type.isin(["Corrective", "Emergency"]),
    "PRIORITY": f.priority, "STATUS": f.status,
    "CREATED_TS": f.created_ts, "STARTED_TS": f.started_ts, "COMPLETED_TS": f.completed_ts,
    "RESPONSE_HOURS": ((f.started_ts - f.created_ts).dt.total_seconds() / 3600).round(4),
    "REPAIR_HOURS": ((f.completed_ts - f.started_ts).dt.total_seconds() / 3600).round(4),
    "SLA_TARGET_HOURS": f.sla_target_hours,
    "LABOR_HOURS": f.labor_hours, "LABOR_COST_EUR": f.labor_cost_eur, "MATERIAL_COST_EUR": f.material_cost_eur,
    "MAINTENANCE_COST_EUR": (f.labor_cost_eur + f.material_cost_eur).round(2),
    "DOWNTIME_HOURS": f.downtime_hours,
    "DOWNTIME_COST_EUR": (f.downtime_hours * f.criticality.map(RATE)).round(2),
    "FIRST_TIME_FIX": f.first_time_fix,
})
resp = (f.started_ts - f.created_ts).dt.total_seconds() / 3600
fact["IS_SLA_MET"] = (resp <= f.sla_target_hours).where(f.started_ts.notna())
fact = fact.sort_values("WORK_ORDER_ID")

fact_budget = budget.merge(dim_site[["SITE_KEY", "SITE_ID"]], left_on="site_id", right_on="SITE_ID")
fact_budget = pd.DataFrame({"MONTH_DATE_KEY": fact_budget.month.dt.strftime("%Y%m%d").astype(int),
                            "SITE_KEY": fact_budget.SITE_KEY, "BUDGET_EUR": fact_budget.budget_eur})

# security bridge for Power BI RLS (normally from GOLD.SEC_USER_REGION)
sec = pd.DataFrame([
    ("regional.lead.west@helios-industrial.example", "West"),
    ("regional.lead.sued@helios-industrial.example", "Süd"),
    ("controller@helios-industrial.example", "*"),
], columns=["USER_PRINCIPAL_NAME", "REGION"])
sec = sec.merge(dim_site[["SITE_KEY", "REGION"]].rename(columns={"REGION": "R"}), how="cross")
sec = sec[(sec.REGION == "*") | (sec.REGION == sec.R)][["USER_PRINCIPAL_NAME", "SITE_KEY"]]

for name, df in {"DIM_DATE": dim_date, "DIM_SITE": dim_site, "DIM_ASSET": dim_asset, "DIM_TECHNICIAN": dim_tech,
                 "DIM_FAILURE_CODE": dim_fc, "FACT_WORK_ORDER": fact, "FACT_BUDGET": fact_budget,
                 "SEC_USER_REGION": sec}.items():
    df.to_csv(G / f"{name}.csv", index=False)
    print(f"{name:<18} {len(df):>7,} rows")
