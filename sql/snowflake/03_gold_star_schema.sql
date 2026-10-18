/* =============================================================================
   ATLAS BI Platform | 03 - GOLD layer: Kimball star schema for Power BI
   -----------------------------------------------------------------------------
   FACT_WORK_ORDER (grain: one work order)  ->  DIM_DATE, DIM_ASSET (SCD2, point-in-time),
   DIM_SITE, DIM_TECHNICIAN, DIM_FAILURE_CODE
   FACT_BUDGET     (grain: site x month)    ->  DIM_SITE, DIM_DATE (month start)

   Rules that keep the Power BI model simple and fast:
   * Integer surrogate keys, no snowflaking, no bi-directional relationships needed.
   * Business logic that is row-level (durations, cost) is computed HERE once;
     aggregation logic (ratios, time intelligence) lives in DAX.
   * Column names are business-friendly; Power BI applies display folders.
   ========================================================================== */
USE ROLE FR_ATLAS_ENGINEER;
USE SCHEMA ATLAS_PROD.GOLD;

-- ---------------------------------------------------------------- configuration owned by Controlling (maintained in Power Apps)
CREATE TABLE IF NOT EXISTS CFG_DOWNTIME_RATE (
    CRITICALITY        VARCHAR(1) PRIMARY KEY,
    EUR_PER_HOUR       NUMBER(10,2) NOT NULL,
    VALID_FROM         DATE NOT NULL,
    APPROVED_BY        VARCHAR NOT NULL,
    COMMENT            VARCHAR
);
MERGE INTO CFG_DOWNTIME_RATE t
USING (SELECT * FROM VALUES ('A',1200,'2024-01-01','Head of Controlling'),
                            ('B', 450,'2024-01-01','Head of Controlling'),
                            ('C', 150,'2024-01-01','Head of Controlling')
       s(CRITICALITY, EUR_PER_HOUR, VALID_FROM, APPROVED_BY)) s
ON t.CRITICALITY = s.CRITICALITY
WHEN NOT MATCHED THEN INSERT (CRITICALITY, EUR_PER_HOUR, VALID_FROM, APPROVED_BY)
                      VALUES (s.CRITICALITY, s.EUR_PER_HOUR, s.VALID_FROM::DATE, s.APPROVED_BY);

-- ---------------------------------------------------------------- DIM_DATE (generated, not loaded)
CREATE OR REPLACE TABLE DIM_DATE AS
WITH d AS (
    SELECT DATEADD(DAY, SEQ4(), '2023-01-01'::DATE) AS DATE_VALUE
    FROM TABLE(GENERATOR(ROWCOUNT => 365 * 6))
)
SELECT
    TO_NUMBER(TO_CHAR(DATE_VALUE, 'YYYYMMDD'))           AS DATE_KEY,
    DATE_VALUE                                           AS DATE,
    YEAR(DATE_VALUE)                                     AS YEAR,
    'Q' || QUARTER(DATE_VALUE)                           AS QUARTER,
    MONTH(DATE_VALUE)                                    AS MONTH_NUMBER,
    TO_CHAR(DATE_VALUE, 'MON')                           AS MONTH_NAME,
    TO_CHAR(DATE_VALUE, 'YYYY-MM')                       AS YEAR_MONTH,
    DATE_TRUNC('MONTH', DATE_VALUE)                      AS MONTH_START,
    WEEKISO(DATE_VALUE)                                  AS ISO_WEEK,
    DAYNAME(DATE_VALUE)                                  AS WEEKDAY_NAME,
    DAYOFWEEKISO(DATE_VALUE) >= 6                        AS IS_WEEKEND,
    DATE_VALUE <= CURRENT_DATE()                         AS IS_PAST
FROM d;
ALTER TABLE DIM_DATE ADD PRIMARY KEY (DATE_KEY);  -- informational; helps Power BI & BI tools

-- ---------------------------------------------------------------- dimensions
CREATE OR REPLACE DYNAMIC TABLE DIM_SITE
  TARGET_LAG = DOWNSTREAM WAREHOUSE = WH_ATLAS_TRANSFORM
AS
SELECT ROW_NUMBER() OVER (ORDER BY SITE_ID) AS SITE_KEY, SITE_ID, SITE_NAME, CITY, REGION,
       COST_CENTER, LATITUDE, LONGITUDE
FROM ATLAS_PROD.SILVER.SITE;

CREATE OR REPLACE DYNAMIC TABLE DIM_ASSET
  TARGET_LAG = DOWNSTREAM WAREHOUSE = WH_ATLAS_TRANSFORM
  COMMENT = 'SCD2: one row per asset version. Facts join point-in-time on CREATED_TS.'
AS
SELECT a.ASSET_SK AS ASSET_KEY, a.ASSET_ID, a.ASSET_NAME, a.ASSET_TYPE, a.MANUFACTURER,
       a.INSTALL_YEAR, YEAR(CURRENT_DATE()) - a.INSTALL_YEAR AS ASSET_AGE_YEARS,
       CASE WHEN YEAR(CURRENT_DATE()) - a.INSTALL_YEAR >= 20 THEN '20+ years'
            WHEN YEAR(CURRENT_DATE()) - a.INSTALL_YEAR >= 10 THEN '10-19 years'
            ELSE '0-9 years' END AS AGE_BAND,
       a.CRITICALITY, a.SITE_ID, a.REPLACEMENT_VALUE_EUR,
       a.VALID_FROM, a.VALID_TO, a.IS_CURRENT
FROM ATLAS_PROD.SILVER.ASSET a;

CREATE OR REPLACE DYNAMIC TABLE DIM_TECHNICIAN
  TARGET_LAG = DOWNSTREAM WAREHOUSE = WH_ATLAS_TRANSFORM
AS
SELECT ROW_NUMBER() OVER (ORDER BY TECHNICIAN_ID) AS TECHNICIAN_KEY, TECHNICIAN_ID, TECHNICIAN_NAME,
       REGION AS HOME_REGION, SKILL_LEVEL, HOURLY_RATE_EUR, HIRE_DATE, EMAIL
FROM ATLAS_PROD.SILVER.TECHNICIAN
UNION ALL
SELECT -1, 'UNKNOWN', 'Unassigned', 'n/a', 'n/a', NULL, NULL, NULL;   -- inferred member

CREATE OR REPLACE DYNAMIC TABLE DIM_FAILURE_CODE
  TARGET_LAG = DOWNSTREAM WAREHOUSE = WH_ATLAS_TRANSFORM
AS
SELECT ROW_NUMBER() OVER (ORDER BY FAILURE_CODE) AS FAILURE_KEY, FAILURE_CODE, FAILURE_DESCRIPTION,
       FAILURE_CATEGORY, FAILURE_CODE <> 'F00' AS IS_FAILURE
FROM ATLAS_PROD.SILVER.FAILURE_CODE;

-- ---------------------------------------------------------------- FACT_WORK_ORDER
CREATE OR REPLACE DYNAMIC TABLE FACT_WORK_ORDER
  TARGET_LAG = '1 hour' WAREHOUSE = WH_ATLAS_TRANSFORM
  CLUSTER BY (CREATED_DATE_KEY)
  COMMENT = 'Grain: one work order. Only DQ_STATUS = VALID and not cancelled.'
AS
SELECT
    w.WORK_ORDER_ID,
    TO_NUMBER(TO_CHAR(w.CREATED_TS, 'YYYYMMDD'))                           AS CREATED_DATE_KEY,
    TO_NUMBER(TO_CHAR(w.COMPLETED_TS, 'YYYYMMDD'))                         AS COMPLETED_DATE_KEY,
    a.ASSET_KEY,                                    -- point-in-time SCD2 key
    s.SITE_KEY,
    COALESCE(t.TECHNICIAN_KEY, -1)                                         AS TECHNICIAN_KEY,
    f.FAILURE_KEY,
    w.WORK_ORDER_TYPE,
    w.WORK_ORDER_TYPE IN ('Corrective', 'Emergency')                       AS IS_FAILURE,
    w.PRIORITY,
    w.STATUS,
    w.CREATED_TS, w.STARTED_TS, w.COMPLETED_TS,
    DATEDIFF(SECOND, w.CREATED_TS, w.STARTED_TS)   / 3600.0                AS RESPONSE_HOURS,
    DATEDIFF(SECOND, w.STARTED_TS, w.COMPLETED_TS) / 3600.0                AS REPAIR_HOURS,
    w.SLA_TARGET_HOURS,
    IFF(w.STARTED_TS IS NULL, NULL,
        DATEDIFF(SECOND, w.CREATED_TS, w.STARTED_TS) / 3600.0 <= w.SLA_TARGET_HOURS) AS IS_SLA_MET,
    w.LABOR_HOURS,
    w.LABOR_COST_EUR,
    w.MATERIAL_COST_EUR,
    w.LABOR_COST_EUR + w.MATERIAL_COST_EUR                                 AS MAINTENANCE_COST_EUR,
    w.DOWNTIME_HOURS,
    w.DOWNTIME_HOURS * r.EUR_PER_HOUR                                      AS DOWNTIME_COST_EUR,
    w.FIRST_TIME_FIX,
    w._FILE                                                                AS SOURCE_FILE   -- lineage to source
FROM ATLAS_PROD.SILVER.WORK_ORDER w
JOIN DIM_ASSET a
  ON a.ASSET_ID = w.ASSET_ID
 AND w.CREATED_TS::DATE BETWEEN a.VALID_FROM AND a.VALID_TO
JOIN DIM_SITE s              ON s.SITE_ID = w.SITE_ID
LEFT JOIN DIM_TECHNICIAN t   ON t.TECHNICIAN_ID = w.TECHNICIAN_ID
JOIN DIM_FAILURE_CODE f      ON f.FAILURE_CODE = w.FAILURE_CODE
JOIN CFG_DOWNTIME_RATE r     ON r.CRITICALITY = a.CRITICALITY
WHERE w.DQ_STATUS = 'VALID'
  AND w.STATUS <> 'Cancelled';

-- ---------------------------------------------------------------- FACT_BUDGET
CREATE OR REPLACE DYNAMIC TABLE FACT_BUDGET
  TARGET_LAG = '1 day' WAREHOUSE = WH_ATLAS_TRANSFORM
AS
SELECT TO_NUMBER(TO_CHAR(b.MONTH_START, 'YYYYMMDD')) AS MONTH_DATE_KEY, s.SITE_KEY, b.BUDGET_EUR
FROM ATLAS_PROD.SILVER.BUDGET b
JOIN DIM_SITE s ON s.SITE_ID = b.SITE_ID;

-- ---------------------------------------------------------------- SCD2 pattern used when master data arrives as a snapshot
-- (alternative to the dynamic table above when the source sends only the current state)
CREATE OR REPLACE PROCEDURE SP_MERGE_ASSET_SCD2()
RETURNS STRING
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    -- 1) close the current version of every asset whose tracked attributes changed
    UPDATE ATLAS_PROD.GOLD.DIM_ASSET_HIST h
       SET VALID_TO = CURRENT_DATE() - 1, IS_CURRENT = FALSE
      FROM ATLAS_PROD.RAW.ASSET_SNAPSHOT_CURRENT s
     WHERE h.ASSET_ID = s.ASSET_ID AND h.IS_CURRENT
       AND HASH(h.CRITICALITY, h.SITE_ID, h.ASSET_TYPE) <> HASH(s.CRITICALITY, s.SITE_ID, s.ASSET_TYPE);

    -- 2) insert a new current version for changed and brand-new assets
    INSERT INTO ATLAS_PROD.GOLD.DIM_ASSET_HIST
          (ASSET_ID, ASSET_NAME, ASSET_TYPE, MANUFACTURER, INSTALL_YEAR, CRITICALITY, SITE_ID,
           REPLACEMENT_VALUE_EUR, VALID_FROM, VALID_TO, IS_CURRENT)
    SELECT s.ASSET_ID, s.ASSET_NAME, s.ASSET_TYPE, s.MANUFACTURER, s.INSTALL_YEAR, s.CRITICALITY, s.SITE_ID,
           s.REPLACEMENT_VALUE_EUR, CURRENT_DATE(), '9999-12-31'::DATE, TRUE
      FROM ATLAS_PROD.RAW.ASSET_SNAPSHOT_CURRENT s
      LEFT JOIN ATLAS_PROD.GOLD.DIM_ASSET_HIST h ON h.ASSET_ID = s.ASSET_ID AND h.IS_CURRENT
     WHERE h.ASSET_ID IS NULL;
    RETURN 'SCD2 merge complete';
END;
$$;
