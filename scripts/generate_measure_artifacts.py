"""
Measures-as-code generator
==========================
Reads powerbi/semantic-model/measures.yaml (single source of truth) and writes:
  powerbi/semantic-model/measures.tmdl   TMDL script (Power BI Desktop > TMDL view > Apply)
  powerbi/semantic-model/measures.dax    DAX query view script with a test EVALUATE
  docs/07_kpi_catalogue.md               business-facing KPI glossary

Run in CI on every pull request so the three artefacts can never drift apart.
"""
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
SM = ROOT / "powerbi" / "semantic-model"
spec = yaml.safe_load((SM / "measures.yaml").read_text(encoding="utf-8"))
T = spec["table"]
measures = spec["measures"]


def q(name: str) -> str:
    return "'" + name.replace("'", "''") + "'"


# ------------------------------------------------------------------ TMDL
tm = [
    "createOrReplace",
    "",
    f"\ttable {T}",
    "",
]
for m in measures:
    tm.append(f"\t\t/// {m['description']}")
    expr = m["expression"].strip().splitlines()
    if len(expr) == 1:
        tm.append(f"\t\tmeasure {q(m['name'])} = {expr[0]}")
    else:
        tm.append(f"\t\tmeasure {q(m['name'])} =")
        tm += [f"\t\t\t\t{line}" if line.strip() else "" for line in expr]
    if m.get("format"):
        tm.append(f"\t\t\tformatString: {m['format']}")
    tm.append(f"\t\t\tdisplayFolder: {m['folder']}")
    tm.append("")
tm += [
    "\t\tcolumn Value",
    "\t\t\tdataType: string",
    "\t\t\tisHidden",
    "\t\t\tsummarizeBy: none",
    "\t\t\tisNameInferred",
    "\t\t\tsourceColumn: [Value]",
    "",
    f"\t\tpartition {T} = calculated",
    "\t\t\tmode: import",
    '\t\t\tsource = ROW ( "Value", BLANK () )',
    "",
]
(SM / "measures.tmdl").write_text("\n".join(tm), encoding="utf-8")

# ------------------------------------------------------------------ DAX query view
dx = [
    "// Power BI Desktop > DAX query view: paste, run, then click 'Update model: Add new measure'",
    "// above each MEASURE (or 'Update model with changes' to add all at once).",
    "// Prerequisite: a table named _Measures exists (Home > Enter data > one empty column).",
    "",
    "DEFINE",
]
for m in measures:
    expr = m["expression"].strip().splitlines()
    dx.append(f"\t// {m['folder']} | owner: {m['owner']}")
    dx.append(f"\tMEASURE {q(T)}[{m['name']}] =")
    dx += [f"\t\t{line}" for line in expr]
    dx.append("")
dx += [
    "// Smoke test: these numbers must equal tests/kpi_reference_values.json",
    "EVALUATE",
    "\tSUMMARIZECOLUMNS (",
    "\t\t'Date'[Year],",
    '\t\t"Work Orders", [Work Orders],',
    '\t\t"Maintenance Cost", [Maintenance Cost],',
    '\t\t"Downtime Cost", [Downtime Cost],',
    '\t\t"Availability %", [Availability %],',
    '\t\t"MTTR (h)", [MTTR (h)],',
    '\t\t"MTBF (h)", [MTBF (h)],',
    '\t\t"PM Ratio %", [PM Ratio %],',
    '\t\t"SLA Compliance %", [SLA Compliance %],',
    '\t\t"First Time Fix %", [First Time Fix %]',
    "\t)",
    "ORDER BY 'Date'[Year]",
]
(SM / "measures.dax").write_text("\n".join(dx), encoding="utf-8")

# ------------------------------------------------------------------ business glossary
md = [
    "# 07 · KPI catalogue (certified measures)",
    "",
    "> Generated from `powerbi/semantic-model/measures.yaml`. This page is what the specialist",
    "> departments read; the YAML is what engineers change. Both always say the same thing.",
    "",
    f"**{len(measures)} certified measures** · every change requires approval by the KPI owner (pull request review).",
    "",
]
folder = None
for m in measures:
    if m["folder"] != folder:
        folder = m["folder"]
        md += ["", f"## {folder[3:]}", "", "| KPI | Definition | Owner | Format |", "|---|---|---|---|"]
    fmt = f"`{m['format']}`" if m.get("format") else "text"
    md.append(f"| **{m['name']}** | {m['description']} | {m['owner']} | {fmt} |")
md += ["", "## DAX definitions", ""]
for m in measures:
    md += [f"<details><summary><b>{m['name']}</b></summary>", "", "```dax", m["expression"].strip(), "```", "", "</details>"]
(ROOT / "docs").mkdir(exist_ok=True)
(ROOT / "docs" / "07_kpi_catalogue.md").write_text("\n".join(md) + "\n", encoding="utf-8")
print(f"generated {len(measures)} measures -> measures.tmdl, measures.dax, docs/07_kpi_catalogue.md")
