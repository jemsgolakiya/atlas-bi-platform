/* =============================================================================
   ATLAS BI Platform | 06 - Analytical SQL: business questions & DAX reconciliation
   -----------------------------------------------------------------------------
   These queries (a) answer the questions raised in the requirements workshops and
   (b) serve as the SQL "second opinion" for every certified DAX measure.
   ========================================================================== */
USE ROLE FR_ATLAS_POWER_USER;
USE WAREHOUSE WH_ATLAS_ADHOC;
USE SCHEMA ATLAS_PROD.GOLD;

-- ---------------------------------------------------------------------------
-- Q1  Certified KPI set per year  (must equal tests/kpi_reference_values.json)
-- ---------------------------------------------------------------------------
WITH asset_count AS (SELECT COUNT(DISTINCT ASSET_ID) AS N FROM DIM_ASSET WHERE IS_CURRENT),
period AS (
    SELECT d.YEAR,
           (DATEDIFF(DAY, MIN(d.DATE), MAX(d.DATE)) + 1) * 24 AS HOURS_IN_PERIOD
    FROM DIM_DATE d WHERE d.DATE BETWEEN '2024-01-01' AND '2026-09-30' GROUP BY d.YEAR
)
SELECT
    p.YEAR,
    COUNT(*)                                                              AS WORK_ORDERS,
    ROUND(SUM(f.MAINTENANCE_COST_EUR), 2)                                 AS MAINTENANCE_COST_EUR,
    ROUND(AVG(IFF(f.IS_FAILURE AND f.STATUS = 'Completed', f.REPAIR_HOURS, NULL)), 3) AS MTTR_HOURS,
    ROUND((a.N * p.HOURS_IN_PERIOD - SUM(f.DOWNTIME_HOURS)) / NULLIF(COUNT_IF(f.IS_FAILURE), 0), 1) AS MTBF_HOURS,
    ROUND((1 - SUM(f.DOWNTIME_HOURS) / (a.N * p.HOURS_IN_PERIOD)) * 100, 3)  AS AVAILABILITY_PCT,
    ROUND(COUNT_IF(f.WORK_ORDER_TYPE = 'Preventive')
          / NULLIF(COUNT_IF(f.WORK_ORDER_TYPE = 'Preventive') + COUNT_IF(f.IS_FAILURE), 0) * 100, 2) AS PM_RATIO_PCT,
    ROUND(AVG(IFF(f.IS_SLA_MET, 1, 0)) * 100, 2)                          AS SLA_COMPLIANCE_PCT,   -- AVG ignores NULL (not started)
    ROUND(AVG(IFF(f.IS_FAILURE, IFF(f.FIRST_TIME_FIX, 1, 0), NULL)) * 100, 2) AS FIRST_TIME_FIX_PCT
FROM FACT_WORK_ORDER f
JOIN DIM_DATE d ON d.DATE_KEY = f.CREATED_DATE_KEY
JOIN period p   ON p.YEAR = d.YEAR
CROSS JOIN asset_count a
GROUP BY p.YEAR, p.HOURS_IN_PERIOD, a.N
ORDER BY p.YEAR;

-- ---------------------------------------------------------------------------
-- Q2  MTBF per asset with the real gaps between consecutive failures (LAG)
--     -> feeds the "repair or replace" decision for Duisburg's pump fleet
-- ---------------------------------------------------------------------------
WITH failures AS (
    SELECT a.ASSET_ID, a.ASSET_NAME, a.ASSET_TYPE, a.CRITICALITY, a.ASSET_AGE_YEARS,
           a.REPLACEMENT_VALUE_EUR, s.SITE_NAME, f.CREATED_TS, f.MAINTENANCE_COST_EUR, f.DOWNTIME_COST_EUR,
           DATEDIFF(HOUR, LAG(f.CREATED_TS) OVER (PARTITION BY a.ASSET_ID ORDER BY f.CREATED_TS), f.CREATED_TS)
               AS HOURS_SINCE_PREV_FAILURE
    FROM FACT_WORK_ORDER f
    JOIN DIM_ASSET a ON a.ASSET_KEY = f.ASSET_KEY
    JOIN DIM_SITE  s ON s.SITE_KEY  = f.SITE_KEY
    WHERE f.IS_FAILURE AND f.CREATED_TS >= DATEADD(MONTH, -12, '2026-09-30'::DATE)
)
SELECT ASSET_NAME, SITE_NAME, ASSET_TYPE, CRITICALITY, ASSET_AGE_YEARS,
       COUNT(*)                                       AS FAILURES_12M,
       ROUND(AVG(HOURS_SINCE_PREV_FAILURE), 0)        AS MTBF_HOURS,
       ROUND(SUM(MAINTENANCE_COST_EUR), 0)            AS MAINT_COST_12M,
       ROUND(SUM(DOWNTIME_COST_EUR), 0)               AS DOWNTIME_COST_12M,
       ANY_VALUE(REPLACEMENT_VALUE_EUR)               AS REPLACEMENT_VALUE,
       ROUND((SUM(MAINTENANCE_COST_EUR) + SUM(DOWNTIME_COST_EUR)) / ANY_VALUE(REPLACEMENT_VALUE_EUR), 2)
                                                      AS COST_TO_REPLACEMENT_RATIO,
       IFF(COST_TO_REPLACEMENT_RATIO >= 1, 'REPLACE', IFF(COST_TO_REPLACEMENT_RATIO >= 0.5, 'REVIEW', 'REPAIR'))
                                                      AS RECOMMENDATION
FROM failures
GROUP BY ALL
HAVING FAILURES_12M >= 6
ORDER BY COST_TO_REPLACEMENT_RATIO DESC
LIMIT 20;

-- ---------------------------------------------------------------------------
-- Q3  Failure Pareto (80/20) on downtime - which failure modes matter
-- ---------------------------------------------------------------------------
SELECT fc.FAILURE_DESCRIPTION, fc.FAILURE_CATEGORY,
       COUNT(*)                                               AS FAILURES,
       ROUND(SUM(f.DOWNTIME_HOURS), 0)                        AS DOWNTIME_H,
       ROUND(RATIO_TO_REPORT(SUM(f.DOWNTIME_HOURS)) OVER () * 100, 1) AS SHARE_PCT,
       ROUND(SUM(SUM(f.DOWNTIME_HOURS)) OVER (ORDER BY SUM(f.DOWNTIME_HOURS) DESC
             ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(SUM(f.DOWNTIME_HOURS)) OVER () * 100, 1) AS CUMULATIVE_PCT
FROM FACT_WORK_ORDER f
JOIN DIM_FAILURE_CODE fc ON fc.FAILURE_KEY = f.FAILURE_KEY
WHERE f.IS_FAILURE AND YEAR(f.CREATED_TS) = 2026
GROUP BY ALL
ORDER BY DOWNTIME_H DESC;

-- ---------------------------------------------------------------------------
-- Q4  PM programme impact: difference-in-differences (Süd vs. control regions)
--     12 months before vs. 12 months after go-live 2025-07-01
-- ---------------------------------------------------------------------------
WITH base AS (
    SELECT IFF(s.REGION = 'Süd', 'Treatment (Süd)', 'Control (other)') AS GRP,
           IFF(f.CREATED_TS < '2025-07-01', 'Before', 'After')         AS PHASE,
           f.*
    FROM FACT_WORK_ORDER f JOIN DIM_SITE s ON s.SITE_KEY = f.SITE_KEY
    WHERE f.CREATED_TS >= '2024-07-01' AND f.CREATED_TS < '2026-07-01'
),
assets AS (
    SELECT IFF(s.REGION = 'Süd', 'Treatment (Süd)', 'Control (other)') AS GRP, COUNT(DISTINCT a.ASSET_ID) AS N
    FROM DIM_ASSET a JOIN DIM_SITE s ON s.SITE_ID = a.SITE_ID WHERE a.IS_CURRENT GROUP BY 1
),
kpi AS (
    SELECT b.GRP, b.PHASE,
           (SUM(b.MAINTENANCE_COST_EUR) + SUM(b.DOWNTIME_COST_EUR)) / ANY_VALUE(a.N) AS TCO_PER_ASSET,
           COUNT_IF(b.WORK_ORDER_TYPE = 'Emergency') / NULLIF(COUNT_IF(b.IS_FAILURE), 0) AS EMERGENCY_SHARE
    FROM base b JOIN assets a ON a.GRP = b.GRP
    GROUP BY b.GRP, b.PHASE
)
SELECT GRP,
       MAX(IFF(PHASE='Before', TCO_PER_ASSET, NULL))  AS TCO_BEFORE,
       MAX(IFF(PHASE='After',  TCO_PER_ASSET, NULL))  AS TCO_AFTER,
       ROUND((TCO_AFTER / TCO_BEFORE - 1) * 100, 1)   AS TCO_CHANGE_PCT
FROM kpi GROUP BY GRP
UNION ALL
SELECT 'Difference-in-differences (pp)', NULL, NULL,
       ROUND(MAX(IFF(GRP LIKE 'Treat%', TCO_CHANGE_PCT, NULL)) - MAX(IFF(GRP LIKE 'Control%', TCO_CHANGE_PCT, NULL)), 1)
FROM (SELECT GRP, (MAX(IFF(PHASE='After', TCO_PER_ASSET, NULL)) / MAX(IFF(PHASE='Before', TCO_PER_ASSET, NULL)) - 1) * 100 AS TCO_CHANGE_PCT
      FROM kpi GROUP BY GRP);

-- ---------------------------------------------------------------------------
-- Q5  Open backlog ageing (snapshot) - buckets for the operations stand-up
-- ---------------------------------------------------------------------------
SELECT s.REGION, f.PRIORITY,
       COUNT_IF(DATEDIFF(DAY, f.CREATED_TS, '2026-09-30') <= 7)              AS AGE_0_7D,
       COUNT_IF(DATEDIFF(DAY, f.CREATED_TS, '2026-09-30') BETWEEN 8 AND 30)  AS AGE_8_30D,
       COUNT_IF(DATEDIFF(DAY, f.CREATED_TS, '2026-09-30') > 30)              AS AGE_30D_PLUS
FROM FACT_WORK_ORDER f JOIN DIM_SITE s ON s.SITE_KEY = f.SITE_KEY
WHERE f.STATUS IN ('Open', 'In Progress')
GROUP BY ALL ORDER BY s.REGION, f.PRIORITY;

-- ---------------------------------------------------------------------------
-- Q6  Budget vs. actual with running YTD and forecast (linear run-rate)
-- ---------------------------------------------------------------------------
WITH actual AS (
    SELECT f.SITE_KEY, DATE_TRUNC('MONTH', f.CREATED_TS)::DATE AS MONTH_START, SUM(f.MAINTENANCE_COST_EUR) AS ACTUAL
    FROM FACT_WORK_ORDER f GROUP BY ALL
),
bud AS (
    SELECT b.SITE_KEY, TO_DATE(b.MONTH_DATE_KEY::STRING, 'YYYYMMDD') AS MONTH_START, b.BUDGET_EUR
    FROM FACT_BUDGET b
)
SELECT s.SITE_NAME,
       SUM(IFF(YEAR(b.MONTH_START) = 2026 AND b.MONTH_START <= '2026-09-01', a.ACTUAL, 0))     AS ACTUAL_YTD,
       SUM(IFF(YEAR(b.MONTH_START) = 2026 AND b.MONTH_START <= '2026-09-01', b.BUDGET_EUR, 0)) AS BUDGET_YTD,
       ROUND((ACTUAL_YTD / NULLIF(BUDGET_YTD, 0) - 1) * 100, 1)                               AS VARIANCE_PCT,
       ROUND(ACTUAL_YTD / 9 * 12, 0)                                                          AS FORECAST_FY,
       SUM(IFF(YEAR(b.MONTH_START) = 2026, b.BUDGET_EUR, 0))                                  AS BUDGET_FY
FROM bud b
LEFT JOIN actual a ON a.SITE_KEY = b.SITE_KEY AND a.MONTH_START = b.MONTH_START
JOIN DIM_SITE s ON s.SITE_KEY = b.SITE_KEY
GROUP BY s.SITE_NAME
ORDER BY VARIANCE_PCT DESC;
