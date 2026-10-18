/* =============================================================================
   ATLAS BI Platform | 04 - Data security: tags, masking, row access
   -----------------------------------------------------------------------------
   Two security layers, deliberately aligned:
     Snowflake  -> protects data for every consumer (SQL users, DirectQuery+SSO,
                   notebooks, exports). Policy-as-code, version controlled.
     Power BI   -> RLS/OLS roles in the semantic model for Import-mode models,
                   because Import refreshes run as one service identity.
   The SAME entitlement table (SECURITY.REGION_ENTITLEMENT) feeds both, so access
   is defined once and audited once (see powerbi/semantic-model/rls_roles.dax).
   ========================================================================== */
USE ROLE FR_ATLAS_GOVERNANCE;
USE DATABASE ATLAS_GOVERNANCE;

-- ---------------------------------------------------------------- classification tags (GDPR / DSGVO)
CREATE TAG IF NOT EXISTS TAGS.PII            ALLOWED_VALUES 'email', 'name', 'salary_related'
  COMMENT = 'Personal data according to Art. 4 GDPR';
CREATE TAG IF NOT EXISTS TAGS.CONFIDENTIALITY ALLOWED_VALUES 'public', 'internal', 'confidential', 'strictly_confidential';
CREATE TAG IF NOT EXISTS TAGS.DATA_OWNER      COMMENT = 'Accountable business owner (department)';

ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.DIM_TECHNICIAN MODIFY COLUMN EMAIL           SET TAG TAGS.PII = 'email';
ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.DIM_TECHNICIAN MODIFY COLUMN TECHNICIAN_NAME SET TAG TAGS.PII = 'name';
ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.DIM_TECHNICIAN MODIFY COLUMN HOURLY_RATE_EUR SET TAG TAGS.PII = 'salary_related';
ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.FACT_WORK_ORDER SET TAG TAGS.CONFIDENTIALITY = 'internal', TAGS.DATA_OWNER = 'Asset Management';
ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.FACT_BUDGET     SET TAG TAGS.CONFIDENTIALITY = 'confidential', TAGS.DATA_OWNER = 'Controlling';

-- ---------------------------------------------------------------- masking policies (attached to TAGS -> new PII columns are protected automatically)
CREATE OR REPLACE MASKING POLICY POLICIES.MP_PII_STRING AS (val STRING) RETURNS STRING ->
  CASE
    WHEN IS_ROLE_IN_SESSION('FR_ATLAS_HR_READER') OR IS_ROLE_IN_SESSION('FR_ATLAS_GOVERNANCE') THEN val
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('ATLAS_GOVERNANCE.TAGS.PII') = 'email'
         THEN REGEXP_REPLACE(val, '^[^@]+', '*****')
    WHEN SYSTEM$GET_TAG_ON_CURRENT_COLUMN('ATLAS_GOVERNANCE.TAGS.PII') = 'name'
         THEN LEFT(val, 1) || '. ' || SPLIT_PART(val, ' ', -1)    -- "Anna Weber" -> "A. Weber"
    ELSE '*** masked ***'
  END;

CREATE OR REPLACE MASKING POLICY POLICIES.MP_PII_NUMBER AS (val NUMBER(8,2)) RETURNS NUMBER(8,2) ->
  CASE WHEN IS_ROLE_IN_SESSION('FR_ATLAS_HR_READER') OR IS_ROLE_IN_SESSION('FR_ATLAS_GOVERNANCE') THEN val
       ELSE NULL END;

ALTER TAG TAGS.PII SET MASKING POLICY POLICIES.MP_PII_STRING, MASKING POLICY POLICIES.MP_PII_NUMBER;

-- ---------------------------------------------------------------- entitlements (single source of truth for row-level security)
CREATE TABLE IF NOT EXISTS SECURITY.REGION_ENTITLEMENT (
    PRINCIPAL        VARCHAR NOT NULL,   -- Snowflake role OR Entra ID UPN (Power BI)
    PRINCIPAL_TYPE   VARCHAR NOT NULL,   -- 'SNOWFLAKE_ROLE' | 'ENTRA_UPN' | 'ENTRA_GROUP'
    REGION           VARCHAR NOT NULL,   -- 'Nord','Süd','West','Ost','Mitte' or '*' = all
    GRANTED_BY       VARCHAR NOT NULL,
    GRANTED_AT       TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    EXPIRES_AT       DATE,               -- forces periodic re-certification
    TICKET_ID        VARCHAR NOT NULL    -- every grant references an approved request
);

INSERT INTO SECURITY.REGION_ENTITLEMENT (PRINCIPAL, PRINCIPAL_TYPE, REGION, GRANTED_BY, EXPIRES_AT, TICKET_ID)
SELECT * FROM VALUES
    ('FR_ATLAS_ANALYST_SUED',            'SNOWFLAKE_ROLE', 'Süd', 'BI Platform Owner', '2027-06-30', 'REQ-1042'),
    ('FR_ATLAS_POWER_USER',              'SNOWFLAKE_ROLE', '*',   'BI Platform Owner', '2027-06-30', 'REQ-1001'),
    ('FR_ATLAS_PBI_SERVICE',             'SNOWFLAKE_ROLE', '*',   'BI Platform Owner', NULL,         'REQ-1000'),
    ('regional.lead.west@helios-industrial.example', 'ENTRA_UPN', 'West', 'Head of Field Service', '2027-03-31', 'REQ-1077');

-- Row access policy keyed on SITE_KEY (region resolved through DIM_SITE)
CREATE OR REPLACE ROW ACCESS POLICY POLICIES.RAP_REGION AS (site_key NUMBER) RETURNS BOOLEAN ->
  IS_ROLE_IN_SESSION('FR_ATLAS_ENGINEER')
  OR IS_ROLE_IN_SESSION('FR_ATLAS_GOVERNANCE')
  OR EXISTS (
       SELECT 1
       FROM ATLAS_GOVERNANCE.SECURITY.REGION_ENTITLEMENT e
       JOIN ATLAS_PROD.GOLD.DIM_SITE s ON (e.REGION = '*' OR e.REGION = s.REGION)
       WHERE s.SITE_KEY = site_key
         AND e.PRINCIPAL_TYPE = 'SNOWFLAKE_ROLE'
         AND IS_ROLE_IN_SESSION(e.PRINCIPAL)
         AND (e.EXPIRES_AT IS NULL OR e.EXPIRES_AT >= CURRENT_DATE())
  );

ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.FACT_WORK_ORDER ADD ROW ACCESS POLICY POLICIES.RAP_REGION ON (SITE_KEY);
ALTER DYNAMIC TABLE ATLAS_PROD.GOLD.FACT_BUDGET     ADD ROW ACCESS POLICY POLICIES.RAP_REGION ON (SITE_KEY);

-- Export of Entra-ID based entitlements for the Power BI RLS bridge table
CREATE OR REPLACE SECURE VIEW ATLAS_PROD.GOLD.SEC_USER_REGION AS
SELECT LOWER(e.PRINCIPAL) AS USER_PRINCIPAL_NAME, s.SITE_KEY
FROM ATLAS_GOVERNANCE.SECURITY.REGION_ENTITLEMENT e
JOIN ATLAS_PROD.GOLD.DIM_SITE s ON (e.REGION = '*' OR e.REGION = s.REGION)
WHERE e.PRINCIPAL_TYPE = 'ENTRA_UPN'
  AND (e.EXPIRES_AT IS NULL OR e.EXPIRES_AT >= CURRENT_DATE());

-- ---------------------------------------------------------------- verification: prove the policies work (run in CI after deploy)
USE ROLE FR_ATLAS_ANALYST_SUED;
SELECT DISTINCT s.REGION FROM ATLAS_PROD.GOLD.FACT_WORK_ORDER f
JOIN ATLAS_PROD.GOLD.DIM_SITE s USING (SITE_KEY);           -- expected: only 'Süd'
SELECT EMAIL, HOURLY_RATE_EUR FROM ATLAS_PROD.GOLD.DIM_TECHNICIAN LIMIT 3; -- expected: masked / NULL

-- Access review: who can see what, and which grants expire within 30 days
USE ROLE FR_ATLAS_GOVERNANCE;
SELECT PRINCIPAL, REGION, GRANTED_BY, EXPIRES_AT, TICKET_ID
FROM ATLAS_GOVERNANCE.SECURITY.REGION_ENTITLEMENT
WHERE EXPIRES_AT <= DATEADD(DAY, 30, CURRENT_DATE())
ORDER BY EXPIRES_AT;
