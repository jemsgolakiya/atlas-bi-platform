/* =============================================================================
   ATLAS BI Platform | Master data back-end for the Power Apps CRUD app
   Target: Azure SQL Database (or Dataverse - see docs/04_power_platform.md for the trade-off)
   -----------------------------------------------------------------------------
   "Audit-proof" (revisionssicher, GoBD-oriented) means:
     1. No change without a trace   -> SYSTEM-VERSIONED TEMPORAL TABLES keep every
                                       version automatically; history is read-only.
     2. Who / when / why            -> ChangedBy, ChangeReason mandatory on every write.
     3. No physical deletes         -> soft delete (IsActive = 0) via stored procedure only.
     4. 4-eyes principle            -> changes to CRITICAL attributes go to a pending
                                       queue and need approval by a second person
                                       (Power Automate approval flow).
     5. App has no table rights     -> the app identity may only EXECUTE procedures.
   ========================================================================== */

CREATE SCHEMA md;      -- master data
GO
CREATE SCHEMA md_hist; -- temporal history (read-only for everyone)
GO

-- ---------------------------------------------------------------- lookup tables
CREATE TABLE md.Criticality (
    Code         CHAR(1)       NOT NULL PRIMARY KEY,
    Description  NVARCHAR(100) NOT NULL
);
INSERT INTO md.Criticality VALUES ('A', N'Safety / production critical'), ('B', N'Important'), ('C', N'Non-critical');

-- ---------------------------------------------------------------- the maintained entity: Asset
CREATE TABLE md.Asset (
    AssetId              VARCHAR(10)    NOT NULL CONSTRAINT PK_Asset PRIMARY KEY,
    AssetName            NVARCHAR(60)   NOT NULL,
    AssetType            NVARCHAR(30)   NOT NULL
        CONSTRAINT CK_Asset_Type CHECK (AssetType IN (N'Transformer', N'Pump', N'Compressor', N'HVAC Unit', N'Conveyor', N'Switchgear')),
    Manufacturer         NVARCHAR(60)   NOT NULL,
    InstallYear          SMALLINT       NOT NULL CONSTRAINT CK_Asset_Year CHECK (InstallYear BETWEEN 1950 AND 2100),
    Criticality          CHAR(1)        NOT NULL CONSTRAINT FK_Asset_Crit REFERENCES md.Criticality(Code),
    SiteId               VARCHAR(5)     NOT NULL,
    ReplacementValueEur  DECIMAL(14,2)  NOT NULL CONSTRAINT CK_Asset_Value CHECK (ReplacementValueEur > 0),
    IsActive             BIT            NOT NULL CONSTRAINT DF_Asset_Active DEFAULT (1),
    ChangedBy            NVARCHAR(128)  NOT NULL,          -- UPN from Entra ID, passed by the app
    ChangeReason         NVARCHAR(400)  NOT NULL,
    RowVersion           ROWVERSION,                       -- optimistic concurrency for the app
    ValidFrom            DATETIME2(3) GENERATED ALWAYS AS ROW START HIDDEN NOT NULL,
    ValidTo              DATETIME2(3) GENERATED ALWAYS AS ROW END   HIDDEN NOT NULL,
    PERIOD FOR SYSTEM_TIME (ValidFrom, ValidTo)
)
WITH (SYSTEM_VERSIONING = ON (HISTORY_TABLE = md_hist.Asset, HISTORY_RETENTION_PERIOD = 10 YEARS));  -- §147 AO / GoBD retention
GO

-- ---------------------------------------------------------------- 4-eyes queue for critical changes
CREATE TABLE md.AssetChangeRequest (
    RequestId        INT IDENTITY(1,1) PRIMARY KEY,
    AssetId          VARCHAR(10)    NOT NULL,
    FieldName        VARCHAR(40)    NOT NULL,      -- 'Criticality' | 'SiteId' | 'IsActive'
    OldValue         NVARCHAR(100)  NULL,
    NewValue         NVARCHAR(100)  NOT NULL,
    RequestedBy      NVARCHAR(128)  NOT NULL,
    RequestedAt      DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    Reason           NVARCHAR(400)  NOT NULL,
    Status           VARCHAR(10)    NOT NULL DEFAULT 'Pending'
        CHECK (Status IN ('Pending', 'Approved', 'Rejected')),
    DecidedBy        NVARCHAR(128)  NULL,
    DecidedAt        DATETIME2(3)   NULL,
    CONSTRAINT CK_FourEyes CHECK (DecidedBy IS NULL OR DecidedBy <> RequestedBy)   -- nobody approves their own change
);
GO

-- ---------------------------------------------------------------- write API used by Power Apps (EXECUTE only)
CREATE OR ALTER PROCEDURE md.usp_Asset_Upsert
    @AssetId VARCHAR(10), @AssetName NVARCHAR(60), @AssetType NVARCHAR(30), @Manufacturer NVARCHAR(60),
    @InstallYear SMALLINT, @Criticality CHAR(1), @SiteId VARCHAR(5), @ReplacementValueEur DECIMAL(14,2),
    @ChangedBy NVARCHAR(128), @ChangeReason NVARCHAR(400), @ExpectedRowVersion BINARY(8) = NULL
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    IF LEN(LTRIM(@ChangeReason)) < 10
        THROW 50001, 'A change reason of at least 10 characters is mandatory.', 1;

    BEGIN TRAN;
    DECLARE @cur TABLE (Criticality CHAR(1), SiteId VARCHAR(5), RowVersion BINARY(8));
    INSERT @cur SELECT Criticality, SiteId, RowVersion FROM md.Asset WITH (UPDLOCK, HOLDLOCK) WHERE AssetId = @AssetId;

    IF NOT EXISTS (SELECT 1 FROM @cur)
    BEGIN
        INSERT md.Asset (AssetId, AssetName, AssetType, Manufacturer, InstallYear, Criticality, SiteId,
                         ReplacementValueEur, ChangedBy, ChangeReason)
        VALUES (@AssetId, @AssetName, @AssetType, @Manufacturer, @InstallYear, @Criticality, @SiteId,
                @ReplacementValueEur, @ChangedBy, @ChangeReason);
    END
    ELSE
    BEGIN
        IF @ExpectedRowVersion IS NOT NULL AND @ExpectedRowVersion <> (SELECT RowVersion FROM @cur)
            THROW 50002, 'The record was changed by another user. Please reload.', 1;

        -- non-critical attributes: applied immediately (still fully versioned)
        UPDATE md.Asset
           SET AssetName = @AssetName, Manufacturer = @Manufacturer, InstallYear = @InstallYear,
               AssetType = @AssetType, ReplacementValueEur = @ReplacementValueEur,
               ChangedBy = @ChangedBy, ChangeReason = @ChangeReason
         WHERE AssetId = @AssetId;

        -- critical attributes: queued for approval (4-eyes)
        INSERT md.AssetChangeRequest (AssetId, FieldName, OldValue, NewValue, RequestedBy, Reason)
        SELECT @AssetId, 'Criticality', c.Criticality, @Criticality, @ChangedBy, @ChangeReason
        FROM @cur c WHERE c.Criticality <> @Criticality
        UNION ALL
        SELECT @AssetId, 'SiteId', c.SiteId, @SiteId, @ChangedBy, @ChangeReason
        FROM @cur c WHERE c.SiteId <> @SiteId;
    END
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE md.usp_Asset_Deactivate
    @AssetId VARCHAR(10), @ChangedBy NVARCHAR(128), @ChangeReason NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    -- soft delete is a critical change -> also goes through approval
    INSERT md.AssetChangeRequest (AssetId, FieldName, OldValue, NewValue, RequestedBy, Reason)
    VALUES (@AssetId, 'IsActive', '1', '0', @ChangedBy, @ChangeReason);
END;
GO

CREATE OR ALTER PROCEDURE md.usp_ChangeRequest_Decide
    @RequestId INT, @Decision VARCHAR(10), @DecidedBy NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT, XACT_ABORT ON;
    BEGIN TRAN;
    UPDATE md.AssetChangeRequest
       SET Status = @Decision, DecidedBy = @DecidedBy, DecidedAt = SYSUTCDATETIME()
     WHERE RequestId = @RequestId AND Status = 'Pending';      -- CK_FourEyes rejects self-approval
    IF @@ROWCOUNT = 0 THROW 50003, 'Request not found or already decided.', 1;

    IF @Decision = 'Approved'
    BEGIN
        DECLARE @a VARCHAR(10), @f VARCHAR(40), @v NVARCHAR(100), @by NVARCHAR(128), @why NVARCHAR(400);
        SELECT @a = AssetId, @f = FieldName, @v = NewValue, @by = RequestedBy, @why = Reason
        FROM md.AssetChangeRequest WHERE RequestId = @RequestId;

        UPDATE md.Asset
           SET Criticality = IIF(@f = 'Criticality', CAST(@v AS CHAR(1)), Criticality),
               SiteId      = IIF(@f = 'SiteId', CAST(@v AS VARCHAR(5)), SiteId),
               IsActive    = IIF(@f = 'IsActive', CAST(@v AS BIT), IsActive),
               ChangedBy   = CONCAT(@by, N' (approved by ', @DecidedBy, N')'),
               ChangeReason = @why
         WHERE AssetId = @a;
    END
    COMMIT;
END;
GO

-- ---------------------------------------------------------------- read API: current state + full audit trail
CREATE OR ALTER VIEW md.vAsset AS
SELECT AssetId, AssetName, AssetType, Manufacturer, InstallYear, Criticality, SiteId,
       ReplacementValueEur, IsActive, ChangedBy, ChangeReason, ValidFrom AS LastChangedAtUtc, RowVersion
FROM md.Asset;
GO

CREATE OR ALTER VIEW md.vAssetAuditTrail AS
SELECT AssetId, AssetName, Criticality, SiteId, ReplacementValueEur, IsActive,
       ChangedBy, ChangeReason, ValidFrom AS ChangedAtUtc,
       NULLIF(ValidTo, '9999-12-31 23:59:59.999') AS SupersededAtUtc
FROM md.Asset FOR SYSTEM_TIME ALL;
GO

-- "What did the master data look like at the time of the audit?"
-- SELECT * FROM md.Asset FOR SYSTEM_TIME AS OF '2026-06-30T23:59:59' WHERE SiteId = 'S05';

-- ---------------------------------------------------------------- least privilege for the app identity
CREATE USER [app-atlas-masterdata] FROM EXTERNAL PROVIDER;     -- Entra ID managed identity / connection
GRANT EXECUTE ON SCHEMA::md TO [app-atlas-masterdata];
GRANT SELECT  ON md.vAsset            TO [app-atlas-masterdata];
GRANT SELECT  ON md.vAssetAuditTrail  TO [app-atlas-masterdata];
GRANT SELECT  ON md.AssetChangeRequest TO [app-atlas-masterdata];
GRANT SELECT  ON md.Criticality        TO [app-atlas-masterdata];
DENY  INSERT, UPDATE, DELETE ON SCHEMA::md      TO [app-atlas-masterdata];
DENY  INSERT, UPDATE, DELETE ON SCHEMA::md_hist TO [app-atlas-masterdata];
GO

-- Sync to Snowflake: Azure Data Factory / Fivetran copies md.vAssetAuditTrail hourly into
-- ATLAS_PROD.RAW.RAW_ASSET -> SILVER.ASSET (SCD2) -> GOLD.DIM_ASSET. One lineage, end to end.
