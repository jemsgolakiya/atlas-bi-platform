"""
KPI reference engine (independent of Power BI)
==============================================
Re-computes every certified KPI in pandas, using the SAME business definitions as the
DAX measures in powerbi/semantic-model/measures.dax. The output is used for:

  * tests/kpi_reference_values.json  -> reconciliation tests: after each deployment the
    CI pipeline runs DAX queries against the published semantic model and compares the
    result with these values (tolerance 0.1%). A certified dataset must reconcile.
  * showcase/data.json                -> aggregated data for the interactive showcase page.

Usage: python scripts/kpi_reference.py
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
D = ROOT / "data"

wo = pd.read_csv(D / "fact_work_order.csv", parse_dates=["created_ts", "started_ts", "completed_ts"])
site = pd.read_csv(D / "dim_site.csv")
asset = pd.read_csv(D / "dim_asset.csv")
tech = pd.read_csv(D / "dim_technician.csv")
fc = pd.read_csv(D / "dim_failure_code.csv")
budget = pd.read_csv(D / "fact_budget.csv", parse_dates=["month"])

# ---------------------------------------------------------------- silver-layer rules
dq_fail = wo.technician_id.isna() | (wo.labor_hours <= 0)
valid = wo[~dq_fail & (wo.status != "Cancelled")].copy()
valid["total_cost"] = valid.labor_cost_eur + valid.material_cost_eur
valid["month"] = valid.created_ts.dt.to_period("M").dt.to_timestamp()
valid["year"] = valid.created_ts.dt.year
valid["is_failure"] = valid.work_order_type.isin(["Corrective", "Emergency"])
valid["response_h"] = (valid.started_ts - valid.created_ts).dt.total_seconds() / 3600
valid["repair_h"] = (valid.completed_ts - valid.started_ts).dt.total_seconds() / 3600
valid = valid.merge(site[["site_id", "site_name", "region"]], on="site_id")
cur_asset = asset[asset.is_current]
valid = valid.merge(cur_asset[["asset_id", "asset_type", "criticality"]], on="asset_id")
# Estimated production loss per downtime hour by asset criticality (agreed with Controlling)
DOWNTIME_RATE = {"A": 1200, "B": 450, "C": 150}
# point-in-time criticality (SCD2) - identical to the GOLD join on VALID_FROM/VALID_TO
pit = asset[["asset_id", "criticality", "valid_from", "valid_to"]].copy()
pit["valid_from"] = pd.to_datetime(pit.valid_from)
pit["valid_to"] = pd.to_datetime(pit.valid_to.replace("9999-12-31", "2262-04-11"))
valid = valid.merge(pit.rename(columns={"criticality": "crit_pit"}), on="asset_id")
valid = valid[(valid.created_ts.dt.normalize() >= valid.valid_from) & (valid.created_ts.dt.normalize() <= valid.valid_to)]
valid = valid.drop(columns=["valid_from", "valid_to"])
valid["downtime_cost"] = valid.downtime_hours * valid.crit_pit.map(DOWNTIME_RATE)

N_ASSETS = cur_asset.asset_id.nunique()
assets_per_site = cur_asset.groupby("site_id").asset_id.nunique()


def kpis(df: pd.DataFrame, n_assets: int, hours_in_period: float) -> dict:
    fail = df[df.is_failure]
    failc = fail[fail.status == "Completed"]
    started = df[df.started_ts.notna()]
    planned = (df.work_order_type == "Preventive").sum()
    reactive = df.is_failure.sum()
    downtime = df.downtime_hours.sum()
    op_hours = n_assets * hours_in_period - downtime
    return {
        "work_orders": int(len(df)),
        "total_cost_eur": round(float(df.total_cost.sum()), 2),
        "labor_hours": round(float(df.labor_hours.sum()), 2),
        "mttr_hours": round(float(failc.repair_h.mean()), 3) if len(failc) else None,
        "mtbf_hours": round(float(op_hours / reactive), 1) if reactive else None,
        "availability_pct": round(float(1 - downtime / (n_assets * hours_in_period)) * 100, 3),
        "pm_ratio_pct": round(float(planned / (planned + reactive)) * 100, 2) if planned + reactive else None,
        "sla_compliance_pct": round(float((started.response_h <= started.sla_target_hours).mean()) * 100, 2),
        "first_time_fix_pct": round(float(fail.first_time_fix.mean()) * 100, 2) if len(fail) else None,
        "emergency_share_pct": round(float((df.work_order_type == "Emergency").sum() / max(reactive, 1)) * 100, 2),
        "cost_per_asset_eur": round(float(df.total_cost.sum() / n_assets), 2),
        "downtime_cost_eur": round(float(df.downtime_cost.sum()), 2),
        "total_cost_of_ownership_eur": round(float(df.total_cost.sum() + df.downtime_cost.sum()), 2),
        "tco_per_asset_eur": round(float((df.total_cost.sum() + df.downtime_cost.sum()) / n_assets), 2),
    }


def period_hours(start: str, end: str) -> float:
    return (pd.Timestamp(end) - pd.Timestamp(start)).total_seconds() / 3600 + 24


ref = {"definitions_version": "1.0.0", "dq": {
    "raw_rows": int(len(wo)), "dq_rejected_rows": int(dq_fail.sum()),
    "cancelled_rows": int((wo.status == "Cancelled").sum()), "valid_rows": int(len(valid))}}
periods = {"FY2024": ("2024-01-01", "2024-12-31"), "FY2025": ("2025-01-01", "2025-12-31"),
           "YTD2026": ("2026-01-01", "2026-09-30")}
ref["portfolio"] = {}
for k, (s, e) in periods.items():
    sub = valid[(valid.created_ts >= s) & (valid.created_ts <= pd.Timestamp(e) + pd.Timedelta(days=1))]
    ref["portfolio"][k] = kpis(sub, N_ASSETS, period_hours(s, e))

ref["by_region_YTD2026"] = {}
for r, g in valid[valid.year == 2026].groupby("region"):
    n = int(cur_asset[cur_asset.site_id.isin(site[site.region == r].site_id)].asset_id.nunique())
    ref["by_region_YTD2026"][r] = kpis(g, n, period_hours("2026-01-01", "2026-09-30"))

(ROOT / "tests").mkdir(exist_ok=True)
(ROOT / "tests" / "kpi_reference_values.json").write_text(json.dumps(ref, indent=2, ensure_ascii=False))

# ======================================================== showcase aggregates
months = sorted(valid.month.unique())
mlabels = [pd.Timestamp(m).strftime("%Y-%m") for m in months]


def monthly(df, col, agg="sum"):
    s = df.groupby("month")[col].agg(agg).reindex(months).fillna(0)
    return [round(float(x), 1) for x in s]


def month_hours(m):
    return pd.Timestamp(m).days_in_month * 24


series = {}
for scope, df, n in [("ALL", valid, N_ASSETS)] + [
        (r, valid[valid.region == r],
         int(cur_asset[cur_asset.site_id.isin(site[site.region == r].site_id)].asset_id.nunique()))
        for r in sorted(site.region.unique())]:
    cost = monthly(df, "total_cost")
    down = df.groupby("month").downtime_hours.sum().reindex(months).fillna(0)
    avail = [round((1 - down[m] / (n * month_hours(m))) * 100, 3) for m in months]
    by_type = {t: [int(x) for x in df[df.work_order_type == t].groupby("month").size().reindex(months).fillna(0)]
               for t in ["Preventive", "Inspection", "Corrective", "Emergency"]}
    st = df[df.started_ts.notna()]
    sla = st.assign(ok=st.response_h <= st.sla_target_hours).groupby("month").ok.mean().reindex(months)
    fail = df[df.is_failure & (df.status == "Completed")]
    mttr = fail.groupby("month").repair_h.mean().reindex(months)
    sites_in = site[site.region == scope].site_id if scope != "ALL" else site.site_id
    bud = budget[budget.site_id.isin(sites_in)].groupby("month").budget_eur.sum().reindex(months).fillna(0)
    series[scope] = {
        "cost": cost, "budget": [round(float(x), 0) for x in bud], "availability": avail,
        "types": by_type, "sla": [round(float(x) * 100, 2) for x in sla],
        "mttr": [round(float(x), 2) for x in mttr], "assets": n,
    }

# site scorecard YTD 2026 vs FY2025 same period
ytd = valid[valid.year == 2026]
ly = valid[(valid.year == 2025) & (valid.created_ts.dt.month <= 9)]
h_ytd = period_hours("2026-01-01", "2026-09-30")
scorecard = []
for s in site.itertuples():
    n = int(assets_per_site.get(s.site_id, 0))
    k = kpis(ytd[ytd.site_id == s.site_id], n, h_ytd)
    k_ly = kpis(ly[ly.site_id == s.site_id], n, period_hours("2025-01-01", "2025-09-30"))
    b = budget[(budget.site_id == s.site_id) & (budget.month.dt.year == 2026)].budget_eur.sum()
    scorecard.append({
        "site_id": s.site_id, "site": s.site_name, "region": s.region, "assets": n,
        "cost": k["total_cost_eur"], "budget": float(b),
        "variance_pct": round((k["total_cost_eur"] / b - 1) * 100, 1) if b else None,
        "availability": k["availability_pct"], "mttr": k["mttr_hours"], "pm_ratio": k["pm_ratio_pct"],
        "sla": k["sla_compliance_pct"], "ftf": k["first_time_fix_pct"],
        "cost_ly": k_ly["total_cost_eur"], "pm_ratio_ly": k_ly["pm_ratio_pct"],
        "availability_ly": k_ly["availability_pct"], "lat": s.latitude, "lon": s.longitude,
    })

# failure pareto YTD (failure work orders)
pareto = (ytd[ytd.is_failure].merge(fc, on="failure_code").groupby(["failure_description", "failure_category"])
          .agg(n=("work_order_id", "size"), cost=("total_cost", "sum"), downtime=("downtime_hours", "sum"))
          .reset_index().sort_values("downtime", ascending=False))
pareto_list = [{"code": r.failure_description, "category": r.failure_category, "n": int(r.n),
                "cost": round(float(r.cost), 0), "downtime": round(float(r.downtime), 1)}
               for r in pareto.itertuples()]

# asset risk ranking: last 6 months failures x criticality weight x age
recent = valid[valid.created_ts >= "2026-04-01"]
risk = (recent[recent.is_failure].groupby("asset_id")
        .agg(failures=("work_order_id", "size"), downtime=("downtime_hours", "sum"), cost=("total_cost", "sum"))
        .reset_index().merge(cur_asset, on="asset_id").merge(site[["site_id", "site_name"]], on="site_id"))
risk["age"] = 2026 - risk.install_year
risk["score"] = (risk.failures * risk.criticality.map({"A": 3, "B": 2, "C": 1})
                 * (1 + risk.age / 20) * (1 + risk.downtime / risk.downtime.max()))
risk = risk.sort_values("score", ascending=False).head(12)
risk_list = [{"asset": r.asset_name, "type": r.asset_type, "site": r.site_name, "crit": r.criticality,
              "age": int(r.age), "failures": int(r.failures), "downtime": round(float(r.downtime), 1),
              "cost": round(float(r.cost), 0), "score": round(float(r.score), 1),
              "repl_value": int(r.replacement_value_eur)} for r in risk.itertuples()]

# technician performance YTD
tp = (ytd.groupby("technician_id").agg(wos=("work_order_id", "size"), hours=("labor_hours", "sum"))
      .reset_index().merge(tech, on="technician_id"))
tp["ftf"] = tp.technician_id.map(ytd[ytd.is_failure].groupby("technician_id").first_time_fix.mean())
st = ytd[ytd.started_ts.notna()]
sla_t = (st.response_h <= st.sla_target_hours).groupby(st.technician_id).mean()
tp["sla"] = tp.technician_id.map(sla_t)
lvl = tp.groupby("skill_level").agg(wos=("wos", "mean"), n=("technician_id", "size"))
# work-order-weighted FTF (identical to [First Time Fix %] sliced by Skill Level)
lvl["ftf"] = ytd[ytd.is_failure].merge(tech[["technician_id", "skill_level"]], on="technician_id") \
    .groupby("skill_level").first_time_fix.mean()
lvl = lvl.reindex(["Junior", "Professional", "Senior", "Expert"])
tech_by_level = [{"level": i, "ftf": round(float(r.ftf) * 100, 1), "avg_wos": round(float(r.wos), 0),
                  "n": int(r.n)} for i, r in lvl.iterrows()]

# PM programme impact (Süd vs rest, 12 months before vs after 2025-07)
def window(df, s, e):
    return df[(df.created_ts >= s) & (df.created_ts < e)]


impact = {}
for grp, df in [("Süd (programme)", valid[valid.region == "Süd"]), ("Other regions", valid[valid.region != "Süd"])]:
    n = int(cur_asset[cur_asset.site_id.isin(df.site_id.unique())].asset_id.nunique())
    b = kpis(window(df, "2024-07-01", "2025-07-01"), n, 365 * 24)
    a = kpis(window(df, "2025-07-01", "2026-07-01"), n, 365 * 24)
    impact[grp] = {"before": b, "after": a}

# repair-or-replace: 12-month TCO vs replacement value (same logic as [Cost to Replacement Ratio])
last12 = valid[(valid.created_ts >= "2025-10-01") & valid.is_failure]
rr = (last12.groupby("asset_id").agg(failures=("work_order_id", "size"), maint=("total_cost", "sum"),
                                      downtime_cost=("downtime_cost", "sum"))
      .reset_index().merge(cur_asset, on="asset_id").merge(site[["site_id", "site_name"]], on="site_id"))
rr["tco"] = rr.maint + rr.downtime_cost
rr["ratio"] = rr.tco / rr.replacement_value_eur
replace_summary = {
    "n_ratio_ge_1": int((rr.ratio >= 1).sum()),
    "duisburg_pumps": int(((rr.ratio >= 1) & (rr.site_id == "S05") & (rr.asset_type == "Pump")).sum()),
    "duisburg_pumps_tco": round(float(rr[(rr.ratio >= 1) & (rr.site_id == "S05") & (rr.asset_type == "Pump")].tco.sum()), 0),
    "duisburg_pumps_capex": int(rr[(rr.ratio >= 1) & (rr.site_id == "S05") & (rr.asset_type == "Pump")].replacement_value_eur.sum()),
}
replace_list = [{"asset": r.asset_name, "type": r.asset_type, "site": r.site_name, "crit": r.criticality,
                 "age": int(2026 - r.install_year), "failures": int(r.failures), "tco": round(float(r.tco), 0),
                 "repl_value": int(r.replacement_value_eur), "ratio": round(float(r.ratio), 2)}
                for r in rr.sort_values("ratio", ascending=False).head(15).itertuples()]

# region-level KPI tiles: YTD 2026 vs same period 2025, plus budget
region_kpis = {}
for scope in ["ALL"] + sorted(site.region.unique()):
    sids = site.site_id if scope == "ALL" else site[site.region == scope].site_id
    n = int(cur_asset[cur_asset.site_id.isin(sids)].asset_id.nunique())
    cur = kpis(ytd[ytd.site_id.isin(sids)], n, h_ytd)
    prev = kpis(ly[ly.site_id.isin(sids)], n, period_hours("2025-01-01", "2025-09-30"))
    bud = float(budget[budget.site_id.isin(sids) & (budget.month.dt.year == 2026)].budget_eur.sum())
    region_kpis[scope] = {"cur": cur, "ly": prev, "budget": bud, "assets": n}

showcase = {
    "region_kpis": region_kpis,
    "replace": replace_list, "replace_summary": replace_summary,
    "generated": pd.Timestamp.now().strftime("%Y-%m-%d"), "months": mlabels, "series": series,
    "scorecard": scorecard, "pareto": pareto_list, "risk": risk_list, "tech_by_level": tech_by_level,
    "impact": impact, "portfolio": ref["portfolio"], "dq": ref["dq"],
}
(ROOT / "showcase").mkdir(exist_ok=True)
(ROOT / "showcase" / "data.json").write_text(json.dumps(showcase, ensure_ascii=False, separators=(",", ":")))

print(json.dumps(ref["portfolio"], indent=1))
print("DQ:", ref["dq"])
print("impact:", json.dumps({k: {p: {m: v[p][m] for m in ("pm_ratio_pct", "emergency_share_pct", "cost_per_asset_eur", "tco_per_asset_eur", "availability_pct")} for p in v} for k, v in impact.items()}, indent=1, ensure_ascii=False))
for s in sorted(scorecard, key=lambda x: -x["variance_pct"])[:12]:
    print(s["site"], s["variance_pct"], s["availability"], s["availability_ly"], s["pm_ratio"], s["sla"], s["mttr"])
print(risk_list[:3])
print(tech_by_level)
