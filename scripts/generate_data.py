"""
ATLAS BI Platform - synthetic data generator
============================================
Generates a realistic, reproducible (seeded) dataset for the fictional company
"Helios Industrial Services GmbH", which operates and maintains industrial assets
(transformers, pumps, compressors, HVAC, conveyors) at 12 German sites.

The data deliberately contains business stories that the dashboards surface:
  1. Duisburg's ageing pump fleet degrades through 2026 -> rising corrective work,
     falling availability, budget overrun (the "burning platform").
  2. A preventive-maintenance (PM) programme launched 2025-07 in region "Süd"
     -> higher PM share, fewer emergencies, lower cost per asset (the "proof").
  3. Seasonal HVAC peaks in summer, heating-related peaks in winter.
  4. Data quality defects (missing technician, negative hours) at a low rate,
     so the DQ tests in sql/snowflake/04_data_quality_tests.sql have something to catch.

Usage:  python scripts/generate_data.py            -> writes CSVs to ./data
"""
from __future__ import annotations

import json
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
rng = np.random.default_rng(SEED)
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data"
OUT.mkdir(exist_ok=True)

START = date(2024, 1, 1)
END = date(2026, 9, 30)
PM_PROGRAMME_START = date(2025, 7, 1)

# --------------------------------------------------------------------------- sites
SITES = [
    # site_id, name, city, region, cost_center, lat, lon
    ("S01", "Frankfurt Ost", "Frankfurt am Main", "Mitte", "CC-4100", 50.12, 8.73),
    ("S02", "Wiesbaden Nord", "Wiesbaden", "Mitte", "CC-4110", 50.10, 8.24),
    ("S03", "Hamburg Hafen", "Hamburg", "Nord", "CC-4200", 53.54, 9.97),
    ("S04", "Bremen Werk", "Bremen", "Nord", "CC-4210", 53.08, 8.80),
    ("S05", "Duisburg Rhein", "Duisburg", "West", "CC-4300", 51.43, 6.76),
    ("S06", "Köln Süd", "Köln", "West", "CC-4310", 50.90, 6.96),
    ("S07", "Dortmund Nord", "Dortmund", "West", "CC-4320", 51.53, 7.46),
    ("S08", "München Ost", "München", "Süd", "CC-4400", 48.13, 11.65),
    ("S09", "Stuttgart Feuerbach", "Stuttgart", "Süd", "CC-4410", 48.81, 9.16),
    ("S10", "Nürnberg Hafen", "Nürnberg", "Süd", "CC-4420", 49.41, 11.06),
    ("S11", "Leipzig Nord", "Leipzig", "Ost", "CC-4500", 51.39, 12.39),
    ("S12", "Dresden Werk", "Dresden", "Ost", "CC-4510", 51.07, 13.73),
]
dim_site = pd.DataFrame(
    SITES, columns=["site_id", "site_name", "city", "region", "cost_center", "latitude", "longitude"]
)

# --------------------------------------------------------------------------- assets
ASSET_TYPES = {
    # type: (share, base monthly failure rate, mean repair hours, mean material €)
    "Transformer": (0.12, 0.08, 9.0, 3800),
    "Pump": (0.26, 0.24, 4.5, 950),
    "Compressor": (0.18, 0.20, 6.0, 1600),
    "HVAC Unit": (0.22, 0.18, 3.5, 700),
    "Conveyor": (0.14, 0.22, 5.0, 1100),
    "Switchgear": (0.08, 0.07, 7.5, 2600),
}
MANUFACTURERS = ["Voltaris", "Nordwerk", "Kessler & Co", "Rheintec", "Alpenstrom", "Brandt Systems"]

assets = []
asset_counter = 1
for site_id, *_ in SITES:
    n = int(rng.integers(62, 92))
    types = rng.choice(list(ASSET_TYPES), size=n, p=[v[0] for v in ASSET_TYPES.values()])
    for t in types:
        install_year = int(rng.integers(1998, 2024))
        if site_id == "S05" and t == "Pump":
            install_year = int(rng.integers(1996, 2006))  # Duisburg's ageing pump fleet
        crit = rng.choice(["A", "B", "C"], p=[0.2, 0.45, 0.35])
        assets.append(
            dict(
                asset_id=f"A{asset_counter:04d}",
                asset_name=f"{t[:4].upper()}-{site_id}-{asset_counter:04d}",
                asset_type=t,
                manufacturer=rng.choice(MANUFACTURERS),
                install_year=install_year,
                criticality=crit,
                site_id=site_id,
                replacement_value_eur=int(
                    {"Transformer": 420000, "Pump": 38000, "Compressor": 95000,
                     "HVAC Unit": 52000, "Conveyor": 76000, "Switchgear": 180000}[t]
                    * rng.uniform(0.7, 1.4)
                ),
            )
        )
        asset_counter += 1
assets_df = pd.DataFrame(assets)

# SCD Type 2 history: ~6% of assets were re-classified in criticality on a change date
scd_rows = []
for a in assets_df.itertuples(index=False):
    base = a._asdict()
    if rng.random() < 0.06:
        change = START + timedelta(days=int(rng.integers(120, (END - START).days - 60)))
        old_crit = rng.choice([c for c in "ABC" if c != a.criticality])
        scd_rows.append({**base, "criticality": old_crit, "valid_from": START.isoformat(),
                         "valid_to": (change - timedelta(days=1)).isoformat(), "is_current": False})
        scd_rows.append({**base, "valid_from": change.isoformat(), "valid_to": "9999-12-31",
                         "is_current": True})
    else:
        scd_rows.append({**base, "valid_from": START.isoformat(), "valid_to": "9999-12-31",
                         "is_current": True})
dim_asset = pd.DataFrame(scd_rows)
dim_asset.insert(0, "asset_sk", range(1, len(dim_asset) + 1))

# --------------------------------------------------------------------------- technicians
FIRST = ["Lukas", "Anna", "Jonas", "Lea", "Felix", "Mia", "Paul", "Emma", "Leon", "Sofia", "Ben",
         "Hannah", "Elias", "Lena", "Noah", "Marie", "Finn", "Laura", "Tim", "Julia", "Mehmet",
         "Aylin", "Piotr", "Katarzyna", "Dimitri", "Elena"]
LAST = ["Müller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker", "Hoffmann",
        "Schulz", "Koch", "Richter", "Klein", "Wolf", "Neumann", "Schwarz", "Yilmaz", "Kowalski",
        "Braun", "Zimmermann", "Hartmann", "Krüger"]
techs = []
for i in range(1, 85):
    region = rng.choice(dim_site.region.unique())
    level = rng.choice(["Junior", "Professional", "Senior", "Expert"], p=[0.25, 0.4, 0.25, 0.1])
    techs.append(dict(
        technician_id=f"T{i:03d}",
        technician_name=f"{rng.choice(FIRST)} {rng.choice(LAST)}",
        region=region,
        skill_level=level,
        hourly_rate_eur={"Junior": 58, "Professional": 72, "Senior": 86, "Expert": 104}[level],
        hire_date=(date(2010, 1, 1) + timedelta(days=int(rng.integers(0, 5200)))).isoformat(),
        email=f"t{i:03d}@helios-industrial.example",
    ))
dim_technician = pd.DataFrame(techs)

# --------------------------------------------------------------------------- failure codes
FAILURES = [
    ("F00", "Planned service - no failure", "Planned"),
    ("F10", "Bearing wear", "Mechanical"), ("F11", "Seal leakage", "Mechanical"),
    ("F12", "Misalignment / vibration", "Mechanical"), ("F13", "Belt / chain failure", "Mechanical"),
    ("F20", "Insulation fault", "Electrical"), ("F21", "Motor winding failure", "Electrical"),
    ("F22", "Control board defect", "Electrical"), ("F23", "Overheating", "Electrical"),
    ("F30", "Sensor / instrumentation fault", "Instrumentation"),
    ("F31", "PLC / software error", "Instrumentation"),
    ("F40", "Refrigerant leak", "Process"), ("F41", "Blockage / fouling", "Process"),
    ("F50", "Operator error", "Human"), ("F90", "No fault found", "Other"),
]
dim_failure_code = pd.DataFrame(FAILURES, columns=["failure_code", "failure_description", "failure_category"])
CORR_CODES = [f[0] for f in FAILURES if f[0] not in ("F00",)]
# Failure-mode mix per asset type (drives a realistic 80/20 Pareto)
FAILURE_MIX = {
    "Pump":        {"F10": 30, "F11": 26, "F12": 12, "F21": 8, "F41": 8, "F30": 5, "F50": 4, "F90": 4, "F23": 3},
    "Compressor":  {"F10": 22, "F23": 20, "F12": 14, "F11": 10, "F21": 10, "F30": 8, "F31": 6, "F50": 5, "F90": 5},
    "HVAC Unit":   {"F40": 32, "F41": 18, "F22": 14, "F30": 12, "F23": 8, "F13": 6, "F50": 5, "F90": 5},
    "Conveyor":    {"F13": 34, "F10": 18, "F12": 16, "F21": 10, "F31": 8, "F50": 8, "F90": 6},
    "Transformer": {"F20": 42, "F23": 22, "F30": 14, "F22": 8, "F90": 8, "F50": 6},
    "Switchgear":  {"F20": 30, "F22": 26, "F31": 16, "F30": 12, "F50": 8, "F90": 8},
}

# --------------------------------------------------------------------------- work orders
site_region = dict(zip(dim_site.site_id, dim_site.region))
techs_by_region = dim_technician.groupby("region").technician_id.apply(list).to_dict()
tech_rate = dict(zip(dim_technician.technician_id, dim_technician.hourly_rate_eur))
tech_level = dict(zip(dim_technician.technician_id, dim_technician.skill_level))

months = pd.date_range(START, END, freq="MS")
SLA_HOURS = {"P1": 4, "P2": 24, "P3": 72, "P4": 240}

rows = []
wo_counter = 1
for m in months:
    mdate = m.date()
    month_idx = (mdate.year - START.year) * 12 + mdate.month - 1
    for a in assets_df.itertuples(index=False):
        p = ASSET_TYPES[a.asset_type]
        age = mdate.year - a.install_year
        region = site_region[a.site_id]
        pm_active = region == "Süd" and mdate >= PM_PROGRAMME_START

        # ---- corrective failure intensity
        lam = p[1] * (1 + 0.035 * max(age - 8, 0))
        if a.asset_type == "HVAC Unit" and mdate.month in (6, 7, 8):
            lam *= 1.9
        if a.asset_type in ("Pump", "Compressor") and mdate.month in (12, 1, 2):
            lam *= 1.35
        if a.site_id == "S05" and a.asset_type == "Pump" and mdate >= date(2025, 10, 1):
            lam *= 1.0 + 0.16 * (month_idx - 21)  # degrading fleet
        if pm_active:
            lam *= 0.52
        lam *= {"A": 1.0, "B": 1.05, "C": 1.15}[a.criticality]
        n_corr = rng.poisson(lam)

        # ---- preventive / inspection
        pm_mean = {"A": 1.0, "B": 0.6, "C": 0.3}[a.criticality] * (1.45 if pm_active else 1.0)
        n_pm = rng.poisson(pm_mean)
        n_insp = rng.poisson(0.2)

        for kind, n in (("Corrective", n_corr), ("Preventive", n_pm), ("Inspection", n_insp)):
            for _ in range(n):
                day = int(rng.integers(0, pd.Timestamp(m).days_in_month))
                created = datetime(mdate.year, mdate.month, 1) + timedelta(days=day, hours=float(rng.uniform(6, 18)))
                wo_type = kind
                if kind == "Corrective" and rng.random() < (0.11 if pm_active else 0.22):
                    wo_type = "Emergency"
                if wo_type == "Emergency":
                    prio = "P1"
                elif wo_type == "Corrective":
                    prio = rng.choice(["P1", "P2", "P3"], p=[0.12, 0.48, 0.40]) if a.criticality == "A" \
                        else rng.choice(["P2", "P3", "P4"], p=[0.35, 0.45, 0.20])
                else:
                    prio = "P4"

                tech_pool = techs_by_region.get(region, dim_technician.technician_id.tolist())
                tech = rng.choice(tech_pool)
                lvl = tech_level[tech]

                if wo_type in ("Corrective", "Emergency"):
                    mix = FAILURE_MIX[a.asset_type]
                    w = np.array(list(mix.values()), dtype=float)
                    fcode = rng.choice(list(mix.keys()), p=w / w.sum())
                    hours = rng.gamma(2.2, p[2] / 2.2) * (1.4 if wo_type == "Emergency" else 1.0)
                    material = rng.gamma(1.6, p[3] / 1.6)
                    downtime = hours * rng.uniform(1.1, 2.6) * (1.6 if wo_type == "Emergency" else 1.0)
                    ftf_p = {"Junior": 0.70, "Professional": 0.80, "Senior": 0.87, "Expert": 0.92}[lvl]
                else:
                    fcode = "F00"
                    hours = rng.gamma(3.0, (2.5 if wo_type == "Preventive" else 1.2) / 3.0)
                    material = rng.gamma(2.0, (p[3] * 0.18) / 2.0)
                    downtime = hours * rng.uniform(0.0, 0.6)
                    ftf_p = 0.97
                ftf = rng.random() < ftf_p

                response_h = rng.gamma(2.0, SLA_HOURS[prio] * 0.38 / 2.0)
                if a.site_id == "S05" and mdate >= date(2026, 1, 1):
                    response_h *= 1.45  # overloaded crew
                started = created + timedelta(hours=float(response_h))
                completed = started + timedelta(hours=float(hours * rng.uniform(1.0, 1.6)))

                status = "Completed"
                if completed.date() > END:
                    status = "In Progress" if started.date() <= END else "Open"
                elif rng.random() < 0.015:
                    status = "Cancelled"

                rows.append(dict(
                    work_order_id=f"WO{wo_counter:07d}",
                    asset_id=a.asset_id, site_id=a.site_id, technician_id=tech,
                    failure_code=fcode, work_order_type=wo_type, priority=prio,
                    created_ts=created, started_ts=started if status != "Open" else None,
                    completed_ts=completed if status == "Completed" else None,
                    status=status,
                    labor_hours=round(float(hours), 2),
                    labor_cost_eur=round(float(hours * tech_rate[tech]), 2),
                    material_cost_eur=round(float(material), 2),
                    downtime_hours=round(float(downtime), 2),
                    sla_target_hours=SLA_HOURS[prio],
                    first_time_fix=bool(ftf),
                ))
                wo_counter += 1

fact = pd.DataFrame(rows).sort_values("created_ts").reset_index(drop=True)
fact["work_order_id"] = [f"WO{i:07d}" for i in range(1, len(fact) + 1)]

# ---- inject a small, realistic rate of DQ defects (caught by DQ tests, excluded downstream)
dq_idx = rng.choice(fact.index, size=int(len(fact) * 0.002), replace=False)
half = len(dq_idx) // 2
fact.loc[dq_idx[:half], "technician_id"] = None
fact.loc[dq_idx[half:], "labor_hours"] = -fact.loc[dq_idx[half:], "labor_hours"]

for c in ("created_ts", "started_ts", "completed_ts"):
    fact[c] = pd.to_datetime(fact[c]).dt.strftime("%Y-%m-%d %H:%M:%S")

# --------------------------------------------------------------------------- budget
clean = fact[(fact.labor_hours > 0) & fact.technician_id.notna() & (fact.status != "Cancelled")].copy()
clean["month"] = pd.to_datetime(clean.created_ts).dt.to_period("M").dt.to_timestamp()
clean["total_cost"] = clean.labor_cost_eur + clean.material_cost_eur
hist = clean[clean.month < "2025-01-01"].groupby("site_id").total_cost.sum() / 12  # 2024 run-rate
budget = []
for m in months:
    for s in dim_site.site_id:
        base = hist.get(s, 0)
        seasonal = 1.12 if m.month in (6, 7, 8) else (1.06 if m.month in (12, 1, 2) else 0.95)
        growth = 1.03 ** (m.year - 2024)
        budget.append(dict(month=m.date().isoformat(), site_id=s,
                           budget_eur=round(base * seasonal * growth * rng.uniform(0.97, 1.03), 0)))
fact_budget = pd.DataFrame(budget)

# --------------------------------------------------------------------------- date dimension
d = pd.DataFrame({"date": pd.date_range(START, END, freq="D")})
d["date_key"] = d.date.dt.strftime("%Y%m%d").astype(int)
d["year"] = d.date.dt.year
d["quarter"] = "Q" + d.date.dt.quarter.astype(str)
d["month_number"] = d.date.dt.month
d["month_name"] = d.date.dt.strftime("%b")
d["year_month"] = d.date.dt.strftime("%Y-%m")
d["iso_week"] = d.date.dt.isocalendar().week.astype(int)
d["weekday_name"] = d.date.dt.strftime("%a")
d["is_weekend"] = d.date.dt.weekday >= 5
d["date"] = d.date.dt.strftime("%Y-%m-%d")
dim_date = d

# --------------------------------------------------------------------------- write
files = {
    "dim_site.csv": dim_site, "dim_asset.csv": dim_asset, "dim_technician.csv": dim_technician,
    "dim_failure_code.csv": dim_failure_code, "dim_date.csv": dim_date,
    "fact_work_order.csv": fact, "fact_budget.csv": fact_budget,
}
for name, df in files.items():
    df.to_csv(OUT / name, index=False)
    print(f"{name:<24} {len(df):>7,} rows")
print("seed:", SEED)
