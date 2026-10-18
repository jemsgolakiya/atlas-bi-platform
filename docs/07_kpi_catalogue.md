# 07 · KPI catalogue (certified measures)

> Generated from `powerbi/semantic-model/measures.yaml`. This page is what the specialist
> departments read; the YAML is what engineers change. Both always say the same thing.

**38 certified measures** · every change requires approval by the KPI owner (pull request review).


## Volume

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Work Orders** | Number of valid, non-cancelled work orders created in the selected period. | Field Service | `#,0` |
| **Failure Work Orders** | Reactive work orders (Corrective + Emergency). Denominator for MTBF, FTF and PM ratio. | Asset Management | `#,0` |
| **Preventive Work Orders** | Planned preventive maintenance work orders. | Asset Management | `#,0` |
| **Emergency Work Orders** | Priority-1 emergency call-outs. | Field Service | `#,0` |
| **Open Backlog** | Work orders that are Open or In Progress (snapshot, ignores the date filter). | Field Service | `#,0` |

## Cost

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Maintenance Cost** | Labour cost + material cost of work orders created in the period (EUR). | Controlling | `#,0 €` |
| **Labor Cost** | Labour hours x technician hourly rate (EUR). | Controlling | `#,0 €` |
| **Material Cost** | Spare parts and consumables (EUR). | Controlling | `#,0 €` |
| **Downtime Cost** | Estimated production loss = downtime hours x EUR/hour rate by asset criticality (A 1,200 / B 450 / C 150), approved by Controlling. | Controlling | `#,0 €` |
| **Total Cost of Ownership** | Maintenance cost + downtime cost. The KPI that makes preventive maintenance comparable with reactive repair. | Controlling | `#,0 €` |
| **Cost per Asset** | Maintenance cost divided by the number of current assets in scope. | Controlling | `#,0 €` |
| **TCO per Asset** | Total cost of ownership divided by the number of current assets in scope. | Controlling | `#,0 €` |

## Budget

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Budget** | Approved monthly maintenance budget (EUR). Granularity is month x site. | Controlling | `#,0 €` |
| **Budget Variance** | Maintenance cost minus budget. Positive = overrun. | Controlling | `+#,0 €;-#,0 €;0 €` |
| **Budget Variance %** | Maintenance cost / budget - 1. Positive = overrun. | Controlling | `+0.0%;-0.0%;0.0%` |
| **Maintenance Cost Forecast FY** | Linear run-rate forecast for the full calendar year of the last loaded date (YTD actual / elapsed days x days in year). | Controlling | `#,0 €` |
| **Budget Status Color** | Hex colour for conditional formatting (field value). Green on/under budget, amber up to +5 %, red above. | BI Platform | text |

## Reliability

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Asset Count** | Number of distinct current assets in scope. Site/Region filters are transferred with TREATAS because Asset is not related to Site (avoids an ambiguous model). | Asset Management | `#,0` |
| **Hours in Period** | Calendar hours in the selected period, capped at the last loaded date. | Asset Management | `#,0` |
| **Downtime Hours** | Asset downtime caused by the work orders (hours). | Asset Management | `#,0.0` |
| **Availability %** | (Asset count x hours in period - downtime) / (asset count x hours in period). | Asset Management | `0.00%` |
| **MTBF (h)** | Mean Time Between Failures = operating hours / number of failure work orders. Higher is better. | Asset Management | `#,0` |
| **MTTR (h)** | Mean Time To Repair = average hours from start to completion of completed failure work orders. Lower is better. | Asset Management | `0.00` |
| **Asset Risk Score** | Failures x criticality weight (A3/B2/C1) x age factor (1 + age/20) x downtime factor. Only evaluated for a single asset; used for the repair-or-replace list. | Asset Management | `0.0` |
| **Cost to Replacement Ratio** | TCO in the period / replacement value of the asset. >= 1 means repairing costs more than replacing. | Asset Management | `0.00` |
| **Downtime Pareto Cumulative %** | Cumulative share of downtime by failure description, sorted descending (80/20 analysis). | Asset Management | `0.0%` |

## Service

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **SLA Compliance %** | Share of started work orders whose response time (created -> started) met the priority target (P1 4h, P2 24h, P3 72h, P4 240h). | Field Service | `0.0%` |
| **First Time Fix %** | Share of failure work orders fixed at the first visit. | Field Service | `0.0%` |
| **PM Ratio %** | Preventive / (Preventive + Failure) work orders. World-class benchmark >= 80 %. | Asset Management | `0.0%` |
| **Emergency Share %** | Emergency work orders / failure work orders. | Field Service | `0.0%` |
| **Avg Response (h)** | Average hours from work order creation to start of work. | Field Service | `0.0` |

## Time Intelligence

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Maintenance Cost YTD** | Year-to-date maintenance cost. | Controlling | `#,0 €` |
| **Maintenance Cost PY** | Maintenance cost in the same period of the previous year. | Controlling | `#,0 €` |
| **Maintenance Cost YoY %** | Change vs. same period previous year. | Controlling | `+0.0%;-0.0%;0.0%` |
| **Maintenance Cost 3M Moving Avg** | Average monthly maintenance cost over the current and two previous months (WINDOW function, requires Year Month on the axis). | Controlling | `#,0 €` |

## Storytelling

| KPI | Definition | Owner | Format |
|---|---|---|---|
| **Executive Narrative** | Auto-generated one-paragraph summary for the executive page (replaces manual commentary). | BI Platform | text |
| **Dynamic Page Title** | Page title that reflects the current slicer selection. | BI Platform | text |
| **Data Freshness** | Shows the newest loaded work order so users always know how current the data is. | BI Platform | text |

## DAX definitions

<details><summary><b>Work Orders</b></summary>

```dax
COUNTROWS ( 'Work Orders' )
```

</details>
<details><summary><b>Failure Work Orders</b></summary>

```dax
CALCULATE ( [Work Orders], 'Work Orders'[Is Failure] = TRUE () )
```

</details>
<details><summary><b>Preventive Work Orders</b></summary>

```dax
CALCULATE ( [Work Orders], 'Work Orders'[Work Order Type] = "Preventive" )
```

</details>
<details><summary><b>Emergency Work Orders</b></summary>

```dax
CALCULATE ( [Work Orders], 'Work Orders'[Work Order Type] = "Emergency" )
```

</details>
<details><summary><b>Open Backlog</b></summary>

```dax
CALCULATE (
    [Work Orders],
    'Work Orders'[Status] IN { "Open", "In Progress" },
    REMOVEFILTERS ( 'Date' )
)
```

</details>
<details><summary><b>Maintenance Cost</b></summary>

```dax
SUM ( 'Work Orders'[Maintenance Cost] )
```

</details>
<details><summary><b>Labor Cost</b></summary>

```dax
SUM ( 'Work Orders'[Labor Cost] )
```

</details>
<details><summary><b>Material Cost</b></summary>

```dax
SUM ( 'Work Orders'[Material Cost] )
```

</details>
<details><summary><b>Downtime Cost</b></summary>

```dax
SUM ( 'Work Orders'[Downtime Cost] )
```

</details>
<details><summary><b>Total Cost of Ownership</b></summary>

```dax
[Maintenance Cost] + [Downtime Cost]
```

</details>
<details><summary><b>Cost per Asset</b></summary>

```dax
DIVIDE ( [Maintenance Cost], [Asset Count] )
```

</details>
<details><summary><b>TCO per Asset</b></summary>

```dax
DIVIDE ( [Total Cost of Ownership], [Asset Count] )
```

</details>
<details><summary><b>Budget</b></summary>

```dax
SUM ( 'Budget'[Budget Amount] )
```

</details>
<details><summary><b>Budget Variance</b></summary>

```dax
IF ( NOT ISBLANK ( [Budget] ), [Maintenance Cost] - [Budget] )
```

</details>
<details><summary><b>Budget Variance %</b></summary>

```dax
IF ( NOT ISBLANK ( [Budget] ), DIVIDE ( [Maintenance Cost], [Budget] ) - 1 )
```

</details>
<details><summary><b>Maintenance Cost Forecast FY</b></summary>

```dax
VAR _lastDate = CALCULATE ( MAX ( 'Work Orders'[Created Date] ), REMOVEFILTERS ( 'Date' ) )
VAR _yearStart = DATE ( YEAR ( _lastDate ), 1, 1 )
VAR _yearEnd = DATE ( YEAR ( _lastDate ), 12, 31 )
VAR _ytd = CALCULATE ( [Maintenance Cost], DATESBETWEEN ( 'Date'[Date], _yearStart, _lastDate ) )
VAR _elapsedDays = INT ( _lastDate - _yearStart ) + 1
VAR _daysInYear = INT ( _yearEnd - _yearStart ) + 1
RETURN
    DIVIDE ( _ytd, _elapsedDays ) * _daysInYear
```

</details>
<details><summary><b>Budget Status Color</b></summary>

```dax
VAR _v = [Budget Variance %]
RETURN
    SWITCH (
        TRUE (),
        ISBLANK ( _v ), "#8A8F98",
        _v > 0.05, "#C0392B",
        _v > 0, "#D68910",
        "#1E8449"
    )
```

</details>
<details><summary><b>Asset Count</b></summary>

```dax
CALCULATE (
    DISTINCTCOUNT ( 'Asset'[Asset ID] ),
    'Asset'[Is Current] = TRUE (),
    TREATAS ( VALUES ( 'Site'[Site ID] ), 'Asset'[Site ID] )
)
```

</details>
<details><summary><b>Hours in Period</b></summary>

```dax
VAR _lastDataDate = CALCULATE ( MAX ( 'Work Orders'[Created Date] ), REMOVEFILTERS () )
VAR _start = MIN ( 'Date'[Date] )
VAR _end = MIN ( MAX ( 'Date'[Date] ), _lastDataDate )
RETURN
    MAX ( ( INT ( _end - _start ) + 1 ) * 24, 0 )
```

</details>
<details><summary><b>Downtime Hours</b></summary>

```dax
SUM ( 'Work Orders'[Downtime Hours] )
```

</details>
<details><summary><b>Availability %</b></summary>

```dax
VAR _capacity = [Asset Count] * [Hours in Period]
RETURN
    DIVIDE ( _capacity - [Downtime Hours], _capacity )
```

</details>
<details><summary><b>MTBF (h)</b></summary>

```dax
DIVIDE (
    [Asset Count] * [Hours in Period] - [Downtime Hours],
    [Failure Work Orders]
)
```

</details>
<details><summary><b>MTTR (h)</b></summary>

```dax
CALCULATE (
    AVERAGE ( 'Work Orders'[Repair Hours] ),
    'Work Orders'[Is Failure] = TRUE (),
    'Work Orders'[Status] = "Completed"
)
```

</details>
<details><summary><b>Asset Risk Score</b></summary>

```dax
IF (
    HASONEVALUE ( 'Asset'[Asset ID] ),
    VAR _crit = CALCULATE ( SELECTEDVALUE ( 'Asset'[Criticality] ), 'Asset'[Is Current] = TRUE () )
    VAR _weight = SWITCH ( _crit, "A", 3, "B", 2, "C", 1, 1 )
    VAR _age = CALCULATE ( SELECTEDVALUE ( 'Asset'[Asset Age] ), 'Asset'[Is Current] = TRUE () )
    VAR _maxDowntime = MAXX ( ALLSELECTED ( 'Asset'[Asset ID] ), [Downtime Hours] )
    RETURN
        [Failure Work Orders] * _weight * ( 1 + DIVIDE ( _age, 20 ) )
            * ( 1 + DIVIDE ( [Downtime Hours], _maxDowntime ) )
)
```

</details>
<details><summary><b>Cost to Replacement Ratio</b></summary>

```dax
IF (
    HASONEVALUE ( 'Asset'[Asset ID] ),
    DIVIDE (
        [Total Cost of Ownership],
        CALCULATE ( MAX ( 'Asset'[Replacement Value] ), 'Asset'[Is Current] = TRUE () )
    )
)
```

</details>
<details><summary><b>Downtime Pareto Cumulative %</b></summary>

```dax
VAR _current = [Downtime Hours]
VAR _table =
    ADDCOLUMNS (
        ALLSELECTED ( 'Failure Code'[Failure Description] ),
        "@downtime", [Downtime Hours]
    )
VAR _cumulative = SUMX ( FILTER ( _table, [@downtime] >= _current ), [@downtime] )
VAR _total = SUMX ( _table, [@downtime] )
RETURN
    IF ( NOT ISBLANK ( _current ), DIVIDE ( _cumulative, _total ) )
```

</details>
<details><summary><b>SLA Compliance %</b></summary>

```dax
DIVIDE (
    CALCULATE ( [Work Orders], 'Work Orders'[Is SLA Met] = TRUE () ),
    CALCULATE ( [Work Orders], NOT ISBLANK ( 'Work Orders'[Started At] ) )
)
```

</details>
<details><summary><b>First Time Fix %</b></summary>

```dax
DIVIDE (
    CALCULATE ( [Failure Work Orders], 'Work Orders'[First Time Fix] = TRUE () ),
    [Failure Work Orders]
)
```

</details>
<details><summary><b>PM Ratio %</b></summary>

```dax
DIVIDE ( [Preventive Work Orders], [Preventive Work Orders] + [Failure Work Orders] )
```

</details>
<details><summary><b>Emergency Share %</b></summary>

```dax
DIVIDE ( [Emergency Work Orders], [Failure Work Orders] )
```

</details>
<details><summary><b>Avg Response (h)</b></summary>

```dax
AVERAGE ( 'Work Orders'[Response Hours] )
```

</details>
<details><summary><b>Maintenance Cost YTD</b></summary>

```dax
TOTALYTD ( [Maintenance Cost], 'Date'[Date] )
```

</details>
<details><summary><b>Maintenance Cost PY</b></summary>

```dax
CALCULATE ( [Maintenance Cost], SAMEPERIODLASTYEAR ( 'Date'[Date] ) )
```

</details>
<details><summary><b>Maintenance Cost YoY %</b></summary>

```dax
VAR _py = [Maintenance Cost PY]
RETURN
    IF ( NOT ISBLANK ( _py ), DIVIDE ( [Maintenance Cost] - _py, _py ) )
```

</details>
<details><summary><b>Maintenance Cost 3M Moving Avg</b></summary>

```dax
AVERAGEX (
    WINDOW ( -2, REL, 0, REL, ALLSELECTED ( 'Date'[Year Month] ), ORDERBY ( 'Date'[Year Month], ASC ) ),
    [Maintenance Cost]
)
```

</details>
<details><summary><b>Executive Narrative</b></summary>

```dax
VAR _cost = [Maintenance Cost]
VAR _var = [Budget Variance %]
VAR _sites =
    ADDCOLUMNS ( VALUES ( 'Site'[Site Name] ), "@var", [Budget Variance %] )
VAR _worst = TOPN ( 1, _sites, [@var], DESC )
VAR _worstName = MAXX ( _worst, 'Site'[Site Name] )
VAR _worstVar = MAXX ( _worst, [@var] )
VAR _scope = SELECTEDVALUE ( 'Site'[Region], "all regions" )
RETURN
    "Maintenance cost for " & _scope & " is "
        & FORMAT ( DIVIDE ( _cost, 1e6 ), "0.00" ) & " M€, "
        & FORMAT ( ABS ( _var ), "0.0%" ) & IF ( _var > 0, " above", " below" ) & " budget. "
        & "Availability is " & FORMAT ( [Availability %], "0.00%" )
        & " with a PM ratio of " & FORMAT ( [PM Ratio %], "0%" ) & ". "
        & IF (
            _worstVar > 0.05,
            "Attention: " & _worstName & " is " & FORMAT ( _worstVar, "0%" ) & " over budget.",
            "No site is more than 5% over budget."
        )
```

</details>
<details><summary><b>Dynamic Page Title</b></summary>

```dax
"Maintenance performance | "
    & SELECTEDVALUE ( 'Site'[Region], "All regions" ) & " | "
    & IF (
        HASONEVALUE ( 'Date'[Year] ),
        FORMAT ( VALUES ( 'Date'[Year] ), "0" ),
        FORMAT ( MIN ( 'Date'[Date] ), "MMM yyyy" ) & " - " & FORMAT ( MAX ( 'Date'[Date] ), "MMM yyyy" )
    )
```

</details>
<details><summary><b>Data Freshness</b></summary>

```dax
"Data as of " & FORMAT ( CALCULATE ( MAX ( 'Work Orders'[Created At] ), REMOVEFILTERS () ), "dd.MM.yyyy HH:mm" )
```

</details>
