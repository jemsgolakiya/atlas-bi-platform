# Power BI layer

| Folder | What it is |
|---|---|
| `power-query/atlas_queries.pq` | All M queries. Parameter `DataSource` switches between Snowflake GOLD and the local CSVs in `data/gold` – the model is identical either way. |
| `semantic-model/measures.yaml` | **Single source of truth** for 38 certified measures (name, folder, format, owner, description, DAX). |
| `semantic-model/measures.tmdl` | Generated. Paste into *TMDL view → Apply*. Creates the `_Measures` table with formats, folders and descriptions. |
| `semantic-model/measures.dax` | Generated. Alternative for *DAX query view* (`DEFINE MEASURE …` + smoke-test `EVALUATE`). |
| `semantic-model/model_objects.tmdl` | Relationships, RLS/OLS roles, the *Time Intelligence* calculation group. |
| `theme/atlas_theme.json` | Corporate report theme (colour-blind-safe palette, consistent card and table styling). |
| `report/REPORT_BLUEPRINT.md` | Page-by-page specification of the report (layout, visuals, interactions, accessibility). |

## Build the model in 15 minutes (no Snowflake account needed)

1. `python scripts/generate_data.py && python scripts/build_gold.py` → creates `data/gold/*.csv`.
2. Power BI Desktop → *File → Options → Preview features*: enable **TMDL view** (and *Store semantic model using TMDL format* if you save as `.pbip`).
3. *Transform data* → create the parameters listed at the top of `atlas_queries.pq`, set `LocalFolder` to your `data\gold` path.
4. Create one blank query per block in `atlas_queries.pq` (name = block header). Disable load for `fnGold`.
5. *Close & Apply*. Mark **Date** as date table (column `Date`), sort `Month Name` by `Month Number`, hide `Security Bridge`.
6. *Model settings*: **Discourage implicit measures = On** (needed for calculation groups).
7. TMDL view → paste `model_objects.tmdl` → **Apply**. Then paste `measures.tmdl` → **Apply**.
8. Hide all `… Key` columns (or run the BPA fix script), apply `theme/atlas_theme.json`.
9. DAX query view → run the `EVALUATE` from `measures.dax` and compare with `tests/kpi_reference_values.json`. They match to the cent.
10. Build the pages from `report/REPORT_BLUEPRINT.md`. Save as **.pbip** so the project is Git-diffable.

## Field parameter: *KPI Selector*

Create via *Modeling → New parameter → Fields*, then replace its DAX with:

```dax
KPI Selector = {
    ( "Maintenance Cost",        NAMEOF ( '_Measures'[Maintenance Cost] ),        0 ),
    ( "Total Cost of Ownership", NAMEOF ( '_Measures'[Total Cost of Ownership] ), 1 ),
    ( "Availability %",          NAMEOF ( '_Measures'[Availability %] ),          2 ),
    ( "MTTR (h)",                NAMEOF ( '_Measures'[MTTR (h)] ),                3 ),
    ( "MTBF (h)",                NAMEOF ( '_Measures'[MTBF (h)] ),                4 ),
    ( "SLA Compliance %",        NAMEOF ( '_Measures'[SLA Compliance %] ),        5 ),
    ( "PM Ratio %",              NAMEOF ( '_Measures'[PM Ratio %] ),              6 )
}
```

## Model design decisions (the "why" a reviewer will ask about)

* **Star schema, single-direction relationships only.** `Asset` is deliberately *not* related to `Site`; `[Asset Count]` uses `TREATAS` instead. This avoids an ambiguous path Site→Asset→Work Orders vs. Site→Work Orders.
* **SCD2 asset dimension.** Work orders point to the asset *version* valid on the creation date, so a criticality reclassification does not rewrite history (downtime cost uses the rate that was valid at the time).
* **Import + incremental refresh** (`RangeStart`/`RangeEnd` fold to Snowflake): archive 5 years, refresh last 3 months, *detect data changes* on `Created At`. DirectQuery is reserved for the near-real-time backlog page via a composite model.
* **Row-level business logic lives in Snowflake, aggregation logic lives in DAX.** Durations, cost and point-in-time keys are computed once upstream; ratios and time intelligence stay in the model where they respond to filter context.
* **Calculation group instead of measure explosion.** 38 measures × 6 time variants would be 228 measures; the calc group keeps it at 38 and ratio measures automatically get *percentage-point* deltas.
* **Security defined once.** RLS reads the same entitlement table as Snowflake's row access policy; OLS hides PII (`Email`, `Hourly Rate`) for everyone except HR.
