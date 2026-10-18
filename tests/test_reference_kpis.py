"""
Unit tests: the GOLD layer (data/gold) reproduces the certified reference KPIs.
Each assertion re-implements the DAX definition from measures.yaml on the gold CSVs,
so a change in either the gold logic or a KPI definition that breaks the numbers fails CI.
Run: python -m pytest tests -q
"""
import json
from pathlib import Path

import pandas as pd
import pytest

ROOT = Path(__file__).resolve().parents[1]
REF = json.loads((ROOT / "tests" / "kpi_reference_values.json").read_text(encoding="utf-8"))
G = ROOT / "data" / "gold"
PERIODS = {"FY2024": ("2024-01-01", "2024-12-31"), "FY2025": ("2025-01-01", "2025-12-31"),
           "YTD2026": ("2026-01-01", "2026-09-30")}


@pytest.fixture(scope="module")
def gold():
    f = pd.read_csv(G / "FACT_WORK_ORDER.csv", parse_dates=["CREATED_TS", "STARTED_TS"])
    a = pd.read_csv(G / "DIM_ASSET.csv")
    return f, a[a.IS_CURRENT].ASSET_ID.nunique()


@pytest.mark.parametrize("period", PERIODS)
def test_dax_definitions_match_reference(gold, period):
    f, n_assets = gold
    start, end = PERIODS[period]
    p = f[(f.CREATED_TS >= start) & (f.CREATED_TS < pd.Timestamp(end) + pd.Timedelta(days=1))]
    hours = ((pd.Timestamp(end) - pd.Timestamp(start)).days + 1) * 24
    ref = REF["portfolio"][period]

    fail = p[p.IS_FAILURE]
    started = p[p.STARTED_TS.notna()]
    prev = (p.WORK_ORDER_TYPE == "Preventive").sum()
    # [Work Orders], [Maintenance Cost], [Downtime Cost]
    assert len(p) == ref["work_orders"]
    assert p.MAINTENANCE_COST_EUR.sum() == pytest.approx(ref["total_cost_eur"], rel=1e-9)
    assert p.DOWNTIME_COST_EUR.sum() == pytest.approx(ref["downtime_cost_eur"], rel=1e-9)
    # [Availability %] = (capacity - downtime) / capacity
    avail = (n_assets * hours - p.DOWNTIME_HOURS.sum()) / (n_assets * hours) * 100
    assert avail == pytest.approx(ref["availability_pct"], abs=1e-3)
    # [MTTR (h)] on completed failures
    mttr = fail[fail.STATUS == "Completed"].REPAIR_HOURS.mean()
    assert mttr == pytest.approx(ref["mttr_hours"], abs=1e-3)
    # [MTBF (h)]
    mtbf = (n_assets * hours - p.DOWNTIME_HOURS.sum()) / len(fail)
    assert mtbf == pytest.approx(ref["mtbf_hours"], abs=0.1)
    # [PM Ratio %], [SLA Compliance %], [First Time Fix %]
    assert prev / (prev + len(fail)) * 100 == pytest.approx(ref["pm_ratio_pct"], abs=0.01)
    assert started.IS_SLA_MET.astype(bool).mean() * 100 == pytest.approx(ref["sla_compliance_pct"], abs=0.01)
    assert fail.FIRST_TIME_FIX.mean() * 100 == pytest.approx(ref["first_time_fix_pct"], abs=0.01)


def test_dq_rules_reject_defects():
    raw = pd.read_csv(ROOT / "data" / "fact_work_order.csv")
    gold = pd.read_csv(G / "FACT_WORK_ORDER.csv")
    assert REF["dq"]["dq_rejected_rows"] > 0, "generator must inject defects so DQ can be demonstrated"
    assert len(gold) == REF["dq"]["valid_rows"]
    assert gold.WORK_ORDER_ID.is_unique
    assert (gold.LABOR_HOURS > 0).all()
    assert len(raw) == REF["dq"]["raw_rows"]


def test_scd2_integrity():
    a = pd.read_csv(G / "DIM_ASSET.csv")
    assert (a.groupby("ASSET_ID").IS_CURRENT.sum() == 1).all(), "exactly one current version per asset"
