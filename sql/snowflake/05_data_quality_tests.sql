/* =============================================================================
   ATLAS BI Platform | 05 - Automated data quality tests + monitoring
   -----------------------------------------------------------------------------
   Each test is a query that returns the number of FAILING rows. Results are logged
   to DQ.TEST_RESULT on every run (Snowflake TASK, hourly). The Power BI
   "Platform Health" page and an alert flow read from this table.
   Severity ERROR  -> blocks certification of the semantic model refresh.
   Severity WARN   -> visible to the data owner, no block.
   ========================================================================== */
USE ROLE FR_ATLAS_ENGINEER;
USE SCHEMA ATLAS_GOVERNANCE.DQ;

CREATE TABLE IF NOT EXISTS TEST_DEFINITION (
    TEST_ID       VARCHAR PRIMARY KEY,
    TABLE_NAME    VARCHAR,
    DESCRIPTION   VARCHAR,
    SEVERITY      VARCHAR,          -- ERROR | WARN
    THRESHOLD     NUMBER,           -- max. failing rows tolerated
    OWNER         VARCHAR,
    TEST_SQL      VARCHAR           -- must return one column FAILING_ROWS
);

CREATE TABLE IF NOT EXISTS TEST_RESULT (
    RUN_ID        VARCHAR,
    TEST_ID       VARCHAR,
    RUN_AT        TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    FAILING_ROWS  NUMBER,
    PASSED        BOOLEAN
);

MERGE INTO TEST_DEFINITION t USING (SELECT * FROM VALUES
 ('DQ001','SILVER.WORK_ORDER','Work orders rejected by silver rules (missing technician, negative hours, ...)','WARN', 100,'Field Service',
  'SELECT COUNT(*) FROM ATLAS_PROD.SILVER.WORK_ORDER WHERE DQ_STATUS = ''REJECTED'''),
 ('DQ002','GOLD.FACT_WORK_ORDER','Primary key uniqueness of WORK_ORDER_ID','ERROR',0,'BI Platform',
  'SELECT COUNT(*) - COUNT(DISTINCT WORK_ORDER_ID) FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER'),
 ('DQ003','GOLD.FACT_WORK_ORDER','Orphan check: valid silver rows that did not reach gold (missing dim / SCD gap)','ERROR',0,'BI Platform',
  'SELECT COUNT(*) FROM ATLAS_PROD.SILVER.WORK_ORDER w WHERE w.DQ_STATUS = ''VALID'' AND w.STATUS <> ''Cancelled'' AND NOT EXISTS (SELECT 1 FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER f WHERE f.WORK_ORDER_ID = w.WORK_ORDER_ID)'),
 ('DQ004','GOLD.DIM_ASSET','SCD2 integrity: exactly one current version per asset','ERROR',0,'Asset Management',
  'SELECT COUNT(*) FROM (SELECT ASSET_ID FROM ATLAS_PROD.GOLD.DIM_ASSET GROUP BY ASSET_ID HAVING SUM(IFF(IS_CURRENT,1,0)) <> 1)'),
 ('DQ005','GOLD.DIM_ASSET','SCD2 integrity: no overlapping validity ranges','ERROR',0,'Asset Management',
  'SELECT COUNT(*) FROM ATLAS_PROD.GOLD.DIM_ASSET a JOIN ATLAS_PROD.GOLD.DIM_ASSET b ON a.ASSET_ID = b.ASSET_ID AND a.ASSET_KEY < b.ASSET_KEY AND a.VALID_FROM <= b.VALID_TO AND b.VALID_FROM <= a.VALID_TO'),
 ('DQ006','GOLD.FACT_WORK_ORDER','Freshness: newest work order older than 26 hours','ERROR',0,'BI Platform',
  'SELECT IFF(MAX(CREATED_TS) < DATEADD(HOUR, -26, CURRENT_TIMESTAMP()), 1, 0) FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER'),
 ('DQ007','GOLD.FACT_WORK_ORDER','Plausibility: single work order cost > 250k EUR','WARN',0,'Controlling',
  'SELECT COUNT(*) FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER WHERE MAINTENANCE_COST_EUR > 250000'),
 ('DQ008','GOLD.FACT_BUDGET','Completeness: every site has a budget for every month of the current year','ERROR',0,'Controlling',
  'SELECT (SELECT COUNT(*) FROM ATLAS_PROD.GOLD.DIM_SITE) * 12 - COUNT(*) FROM ATLAS_PROD.GOLD.FACT_BUDGET WHERE LEFT(MONTH_DATE_KEY::STRING, 4) = YEAR(CURRENT_DATE())::STRING'),
 ('DQ009','GOLD.FACT_WORK_ORDER','Volume anomaly: today vs. 28-day average deviates > 3 sigma','WARN',0,'BI Platform',
  'WITH d AS (SELECT CREATED_DATE_KEY, COUNT(*) n FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER WHERE CREATED_TS >= DATEADD(DAY,-29,CURRENT_DATE()) GROUP BY 1) SELECT IFF(ABS(MAX(IFF(CREATED_DATE_KEY = TO_NUMBER(TO_CHAR(CURRENT_DATE()-1,''YYYYMMDD'')), n, NULL)) - AVG(n)) > 3 * STDDEV(n), 1, 0) FROM d')
) s(TEST_ID, TABLE_NAME, DESCRIPTION, SEVERITY, THRESHOLD, OWNER, TEST_SQL)
ON t.TEST_ID = s.TEST_ID
WHEN MATCHED THEN UPDATE SET DESCRIPTION = s.DESCRIPTION, SEVERITY = s.SEVERITY, THRESHOLD = s.THRESHOLD, OWNER = s.OWNER, TEST_SQL = s.TEST_SQL
WHEN NOT MATCHED THEN INSERT VALUES (s.TEST_ID, s.TABLE_NAME, s.DESCRIPTION, s.SEVERITY, s.THRESHOLD, s.OWNER, s.TEST_SQL);

-- ---------------------------------------------------------------- generic test runner
CREATE OR REPLACE PROCEDURE SP_RUN_DQ_TESTS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    run_id   VARCHAR DEFAULT UUID_STRING();
    failing  NUMBER;
    errors   NUMBER DEFAULT 0;
    c1 CURSOR FOR SELECT TEST_ID, TEST_SQL, SEVERITY, THRESHOLD FROM ATLAS_GOVERNANCE.DQ.TEST_DEFINITION;
BEGIN
    FOR rec IN c1 DO
        LET rs RESULTSET := (EXECUTE IMMEDIATE rec.TEST_SQL);
        LET cur CURSOR FOR rs;
        OPEN cur;
        FETCH cur INTO failing;
        CLOSE cur;
        INSERT INTO ATLAS_GOVERNANCE.DQ.TEST_RESULT (RUN_ID, TEST_ID, FAILING_ROWS, PASSED)
        VALUES (:run_id, :rec.TEST_ID, :failing, :failing <= :rec.THRESHOLD);
        IF (failing > rec.THRESHOLD AND rec.SEVERITY = 'ERROR') THEN
            errors := errors + 1;
        END IF;
    END FOR;
    RETURN OBJECT_CONSTRUCT('run_id', run_id, 'blocking_errors', errors);
END;
$$;

CREATE OR REPLACE TASK TSK_DQ_HOURLY
  WAREHOUSE = WH_ATLAS_TRANSFORM
  SCHEDULE  = 'USING CRON 15 * * * * Europe/Berlin'
  COMMENT   = 'Runs after dynamic table refresh; results drive the Platform Health report'
AS CALL SP_RUN_DQ_TESTS();
ALTER TASK TSK_DQ_HOURLY RESUME;

-- ---------------------------------------------------------------- latest status per test (source for Power BI "Platform Health")
CREATE OR REPLACE VIEW V_DQ_LATEST AS
SELECT d.TEST_ID, d.TABLE_NAME, d.DESCRIPTION, d.SEVERITY, d.OWNER, r.RUN_AT, r.FAILING_ROWS, r.PASSED
FROM TEST_DEFINITION d
JOIN TEST_RESULT r ON r.TEST_ID = d.TEST_ID
QUALIFY ROW_NUMBER() OVER (PARTITION BY d.TEST_ID ORDER BY r.RUN_AT DESC) = 1;

-- ---------------------------------------------------------------- cost & usage monitoring of the BI warehouse
CREATE OR REPLACE VIEW ATLAS_GOVERNANCE.MONITORING.V_BI_QUERY_COST AS
SELECT DATE_TRUNC('DAY', START_TIME) AS DAY, WAREHOUSE_NAME, USER_NAME, ROLE_NAME,
       COUNT(*)                                   AS QUERIES,
       ROUND(SUM(TOTAL_ELAPSED_TIME) / 1000 / 60, 1) AS ELAPSED_MIN,
       ROUND(AVG(TOTAL_ELAPSED_TIME) / 1000, 2)   AS AVG_SECONDS,
       SUM(IFF(TOTAL_ELAPSED_TIME > 10000, 1, 0)) AS SLOW_QUERIES_10S
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME LIKE 'WH_ATLAS%' AND START_TIME >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
GROUP BY ALL;
