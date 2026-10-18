-- =============================================================================
-- ATLAS BI Platform | Databricks (Unity Catalog + Delta Lake) equivalent
-- -----------------------------------------------------------------------------
-- Same architecture, Databricks flavour - shows the design is platform-agnostic.
--   Snowflake database/schema  ->  Unity Catalog catalog/schema
--   Dynamic tables             ->  Delta Live Tables / materialized views
--   Masking + row access       ->  UC column masks + row filters
--   Power BI connects through the Databricks connector (SQL warehouse, Entra SSO)
-- =============================================================================

CREATE CATALOG IF NOT EXISTS atlas_prod;
CREATE SCHEMA  IF NOT EXISTS atlas_prod.silver;
CREATE SCHEMA  IF NOT EXISTS atlas_prod.gold;
CREATE SCHEMA  IF NOT EXISTS atlas_prod.governance;

-- ---------------------------------------------------------------- silver: Delta table with constraints (enforced on write)
CREATE TABLE IF NOT EXISTS atlas_prod.silver.work_order (
  work_order_id      STRING NOT NULL,
  asset_id           STRING NOT NULL,
  site_id            STRING NOT NULL,
  technician_id      STRING,
  failure_code       STRING,
  work_order_type    STRING,
  priority           STRING,
  created_ts         TIMESTAMP,
  started_ts         TIMESTAMP,
  completed_ts       TIMESTAMP,
  status             STRING,
  labor_hours        DECIMAL(10,2),
  labor_cost_eur     DECIMAL(14,2),
  material_cost_eur  DECIMAL(14,2),
  downtime_hours     DECIMAL(10,2),
  sla_target_hours   INT,
  first_time_fix     BOOLEAN,
  _ingested_at       TIMESTAMP,
  CONSTRAINT valid_type CHECK (work_order_type IN ('Preventive','Inspection','Corrective','Emergency'))
) USING DELTA
CLUSTER BY (created_ts)
TBLPROPERTIES ('delta.enableChangeDataFeed' = 'true');

-- Idempotent upsert from the bronze stream
MERGE INTO atlas_prod.silver.work_order AS t
USING (
  SELECT * FROM atlas_prod.bronze.work_order_updates
  QUALIFY ROW_NUMBER() OVER (PARTITION BY work_order_id ORDER BY _ingested_at DESC) = 1
) AS s
ON t.work_order_id = s.work_order_id
WHEN MATCHED AND s._ingested_at > t._ingested_at THEN UPDATE SET *
WHEN NOT MATCHED THEN INSERT *;

-- ---------------------------------------------------------------- gold: SCD2 asset dimension with a single MERGE
-- (the "union trick": changed rows appear twice - once to close, once to insert)
MERGE INTO atlas_prod.gold.dim_asset AS t
USING (
  SELECT s.asset_id AS merge_key, s.* FROM atlas_prod.silver.asset_current s
  UNION ALL
  SELECT NULL AS merge_key, s.*
  FROM atlas_prod.silver.asset_current s
  JOIN atlas_prod.gold.dim_asset d
    ON d.asset_id = s.asset_id AND d.is_current
   AND (d.criticality <> s.criticality OR d.site_id <> s.site_id)
) AS s
ON t.asset_id = s.merge_key AND t.is_current
WHEN MATCHED AND (t.criticality <> s.criticality OR t.site_id <> s.site_id) THEN
  UPDATE SET t.is_current = false, t.valid_to = current_date() - INTERVAL 1 DAY
WHEN NOT MATCHED THEN
  INSERT (asset_id, asset_name, asset_type, criticality, site_id, replacement_value_eur, valid_from, valid_to, is_current)
  VALUES (s.asset_id, s.asset_name, s.asset_type, s.criticality, s.site_id, s.replacement_value_eur,
          current_date(), DATE'9999-12-31', true);

-- ---------------------------------------------------------------- governance: UC row filter + column mask
CREATE OR REPLACE FUNCTION atlas_prod.governance.rf_region(region STRING)
RETURNS BOOLEAN
RETURN is_account_group_member('atlas-engineers')
    OR EXISTS (SELECT 1 FROM atlas_prod.governance.region_entitlement e
               WHERE (e.region = '*' OR e.region = region)
                 AND is_account_group_member(e.entra_group));

CREATE OR REPLACE FUNCTION atlas_prod.governance.cm_email(email STRING)
RETURN CASE WHEN is_account_group_member('atlas-hr-readers') THEN email
            ELSE regexp_replace(email, '^[^@]+', '*****') END;

ALTER TABLE atlas_prod.gold.fact_work_order_by_region SET ROW FILTER atlas_prod.governance.rf_region ON (region);
ALTER TABLE atlas_prod.gold.dim_technician ALTER COLUMN email SET MASK atlas_prod.governance.cm_email;

-- Least privilege grants to Entra ID groups (synced via SCIM)
GRANT USE CATALOG ON CATALOG atlas_prod TO `atlas-bi-readers`;
GRANT USE SCHEMA, SELECT ON SCHEMA atlas_prod.gold TO `atlas-bi-readers`;
GRANT USE SCHEMA, SELECT, MODIFY ON SCHEMA atlas_prod.silver TO `atlas-engineers`;

-- Lineage & audit come for free in Unity Catalog:
SELECT event_time, user_identity.email, action_name, request_params
FROM system.access.audit
WHERE service_name = 'unityCatalog' AND request_params.full_name_arg LIKE 'atlas_prod.gold.%'
ORDER BY event_time DESC LIMIT 100;
