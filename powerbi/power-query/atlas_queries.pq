// =============================================================================
// ATLAS semantic model | Power Query (M)
// -----------------------------------------------------------------------------
// One switch, two sources, identical result:
//   DataSource = "Snowflake" -> ATLAS_<Environment>.GOLD (production, query folding)
//   DataSource = "LocalCSV"  -> data/gold/*.csv  (portfolio demo, no account needed)
// Environment is overridden per stage by deployment-pipeline parameter rules,
// so the SAME .pbix/.pbip goes DEV -> TEST -> PROD without manual edits.
// Create each block below as a separate query with the name in the header.
// =============================================================================


// ---------------------------------------------------------------- PARAMETERS
// DataSource          (Text, list: "Snowflake","LocalCSV")    = "LocalCSV"
// Environment         (Text, list: "DEV","TEST","PROD")        = "DEV"
// SnowflakeServer     (Text) = "helios-atlas.west-europe.azure.snowflakecomputing.com"
// SnowflakeWarehouse  (Text) = "WH_ATLAS_BI"
// LocalFolder         (Text) = "C:\repos\atlas-bi-platform\data\gold"
// RangeStart          (DateTime) = #datetime(2024, 1, 1, 0, 0, 0)   // incremental refresh
// RangeEnd            (DateTime) = #datetime(2030, 1, 1, 0, 0, 0)


// ---------------------------------------------------------------- fnGold  (function, not loaded)
let
    fnGold = (tableName as text) as table =>
        if DataSource = "Snowflake" then
            let
                Source   = Snowflake.Databases(SnowflakeServer, SnowflakeWarehouse,
                                [Role = "FR_ATLAS_PBI_SERVICE", Implementation = "2.0"]),
                Database = Source{[Name = "ATLAS_" & Environment, Kind = "Database"]}[Data],
                Schema   = Database{[Name = "GOLD", Kind = "Schema"]}[Data],
                Object   = Table.SelectRows(Schema, each [Name] = tableName){0}[Data]
            in
                Object
        else
            let
                Csv      = Csv.Document(File.Contents(LocalFolder & "\" & tableName & ".csv"),
                                [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]),
                Promoted = Table.PromoteHeaders(Csv, [PromoteAllScalars = true])
            in
                Promoted
in
    fnGold


// ---------------------------------------------------------------- Work Orders
let
    Source  = fnGold("FACT_WORK_ORDER"),
    Typed   = Table.TransformColumnTypes(Source, {
                {"WORK_ORDER_ID", type text}, {"ASSET_KEY", Int64.Type}, {"SITE_KEY", Int64.Type},
                {"TECHNICIAN_KEY", Int64.Type}, {"FAILURE_KEY", Int64.Type},
                {"WORK_ORDER_TYPE", type text}, {"IS_FAILURE", type logical}, {"PRIORITY", type text},
                {"STATUS", type text}, {"CREATED_TS", type datetime}, {"STARTED_TS", type datetime},
                {"COMPLETED_TS", type datetime}, {"RESPONSE_HOURS", type number}, {"REPAIR_HOURS", type number},
                {"SLA_TARGET_HOURS", Int64.Type}, {"IS_SLA_MET", type logical}, {"LABOR_HOURS", type number},
                {"LABOR_COST_EUR", Currency.Type}, {"MATERIAL_COST_EUR", Currency.Type},
                {"MAINTENANCE_COST_EUR", Currency.Type}, {"DOWNTIME_HOURS", type number},
                {"DOWNTIME_COST_EUR", Currency.Type}, {"FIRST_TIME_FIX", type logical}}, "en-US"),
    // Incremental refresh window (folds to Snowflake as a WHERE clause)
    Window  = Table.SelectRows(Typed, each [CREATED_TS] >= RangeStart and [CREATED_TS] < RangeEnd),
    AddCreatedDate   = Table.AddColumn(Window, "Created Date", each DateTime.Date([CREATED_TS]), type date),
    AddCompletedDate = Table.AddColumn(AddCreatedDate, "Completed Date",
                           each if [COMPLETED_TS] = null then null else DateTime.Date([COMPLETED_TS]), type date),
    Selected = Table.SelectColumns(AddCompletedDate, {
                "WORK_ORDER_ID", "Created Date", "Completed Date", "ASSET_KEY", "SITE_KEY", "TECHNICIAN_KEY",
                "FAILURE_KEY", "WORK_ORDER_TYPE", "IS_FAILURE", "PRIORITY", "STATUS", "CREATED_TS", "STARTED_TS",
                "COMPLETED_TS", "RESPONSE_HOURS", "REPAIR_HOURS", "SLA_TARGET_HOURS", "IS_SLA_MET", "LABOR_HOURS",
                "LABOR_COST_EUR", "MATERIAL_COST_EUR", "MAINTENANCE_COST_EUR", "DOWNTIME_HOURS",
                "DOWNTIME_COST_EUR", "FIRST_TIME_FIX"}),
    Renamed  = Table.RenameColumns(Selected, {
                {"WORK_ORDER_ID", "Work Order ID"}, {"ASSET_KEY", "Asset Key"}, {"SITE_KEY", "Site Key"},
                {"TECHNICIAN_KEY", "Technician Key"}, {"FAILURE_KEY", "Failure Key"},
                {"WORK_ORDER_TYPE", "Work Order Type"}, {"IS_FAILURE", "Is Failure"}, {"PRIORITY", "Priority"},
                {"STATUS", "Status"}, {"CREATED_TS", "Created At"}, {"STARTED_TS", "Started At"},
                {"COMPLETED_TS", "Completed At"}, {"RESPONSE_HOURS", "Response Hours"},
                {"REPAIR_HOURS", "Repair Hours"}, {"SLA_TARGET_HOURS", "SLA Target Hours"},
                {"IS_SLA_MET", "Is SLA Met"}, {"LABOR_HOURS", "Labor Hours"}, {"LABOR_COST_EUR", "Labor Cost"},
                {"MATERIAL_COST_EUR", "Material Cost"}, {"MAINTENANCE_COST_EUR", "Maintenance Cost"},
                {"DOWNTIME_HOURS", "Downtime Hours"}, {"DOWNTIME_COST_EUR", "Downtime Cost"},
                {"FIRST_TIME_FIX", "First Time Fix"}})
in
    Renamed


// ---------------------------------------------------------------- Budget
let
    Source  = fnGold("FACT_BUDGET"),
    Typed   = Table.TransformColumnTypes(Source, {{"MONTH_DATE_KEY", Int64.Type}, {"SITE_KEY", Int64.Type},
                                                  {"BUDGET_EUR", Currency.Type}}, "en-US"),
    AddDate = Table.AddColumn(Typed, "Month Start",
                each #date(Number.IntegerDivide([MONTH_DATE_KEY], 10000),
                           Number.Mod(Number.IntegerDivide([MONTH_DATE_KEY], 100), 100), 1), type date),
    Result  = Table.RenameColumns(Table.RemoveColumns(AddDate, {"MONTH_DATE_KEY"}),
                {{"SITE_KEY", "Site Key"}, {"BUDGET_EUR", "Budget Amount"}})
in
    Result


// ---------------------------------------------------------------- Date
let
    Source  = fnGold("DIM_DATE"),
    Typed   = Table.TransformColumnTypes(Source, {{"DATE", type date}, {"YEAR", Int64.Type},
                {"QUARTER", type text}, {"MONTH_NUMBER", Int64.Type}, {"MONTH_NAME", type text},
                {"YEAR_MONTH", type text}, {"ISO_WEEK", Int64.Type}, {"WEEKDAY_NAME", type text},
                {"IS_WEEKEND", type logical}}, "en-US"),
    Result  = Table.RenameColumns(
                Table.SelectColumns(Typed, {"DATE", "YEAR", "QUARTER", "MONTH_NUMBER", "MONTH_NAME",
                                            "YEAR_MONTH", "ISO_WEEK", "WEEKDAY_NAME", "IS_WEEKEND"}),
                {{"DATE", "Date"}, {"YEAR", "Year"}, {"QUARTER", "Quarter"}, {"MONTH_NUMBER", "Month Number"},
                 {"MONTH_NAME", "Month Name"}, {"YEAR_MONTH", "Year Month"}, {"ISO_WEEK", "ISO Week"},
                 {"WEEKDAY_NAME", "Weekday"}, {"IS_WEEKEND", "Is Weekend"}})
in
    Result


// ---------------------------------------------------------------- Site
let
    Source = fnGold("DIM_SITE"),
    Typed  = Table.TransformColumnTypes(Source, {{"SITE_KEY", Int64.Type}, {"LATITUDE", type number},
                                                 {"LONGITUDE", type number}}, "en-US"),
    Result = Table.RenameColumns(Typed, {{"SITE_KEY", "Site Key"}, {"SITE_ID", "Site ID"},
                {"SITE_NAME", "Site Name"}, {"CITY", "City"}, {"REGION", "Region"},
                {"COST_CENTER", "Cost Center"}, {"LATITUDE", "Latitude"}, {"LONGITUDE", "Longitude"}})
in
    Result


// ---------------------------------------------------------------- Asset  (SCD2 - all versions)
let
    Source = fnGold("DIM_ASSET"),
    Typed  = Table.TransformColumnTypes(Source, {{"ASSET_KEY", Int64.Type}, {"INSTALL_YEAR", Int64.Type},
                {"ASSET_AGE_YEARS", Int64.Type}, {"REPLACEMENT_VALUE_EUR", Currency.Type},
                {"VALID_FROM", type date}, {"VALID_TO", type date}, {"IS_CURRENT", type logical}}, "en-US"),
    Result = Table.RenameColumns(
                Table.SelectColumns(Typed, {"ASSET_KEY", "ASSET_ID", "ASSET_NAME", "ASSET_TYPE", "MANUFACTURER",
                    "INSTALL_YEAR", "ASSET_AGE_YEARS", "AGE_BAND", "CRITICALITY", "SITE_ID",
                    "REPLACEMENT_VALUE_EUR", "VALID_FROM", "VALID_TO", "IS_CURRENT"}),
                {{"ASSET_KEY", "Asset Key"}, {"ASSET_ID", "Asset ID"}, {"ASSET_NAME", "Asset Name"},
                 {"ASSET_TYPE", "Asset Type"}, {"MANUFACTURER", "Manufacturer"}, {"INSTALL_YEAR", "Install Year"},
                 {"ASSET_AGE_YEARS", "Asset Age"}, {"AGE_BAND", "Age Band"}, {"CRITICALITY", "Criticality"},
                 {"SITE_ID", "Site ID"}, {"REPLACEMENT_VALUE_EUR", "Replacement Value"},
                 {"VALID_FROM", "Valid From"}, {"VALID_TO", "Valid To"}, {"IS_CURRENT", "Is Current"}})
in
    Result


// ---------------------------------------------------------------- Technician
let
    Source = fnGold("DIM_TECHNICIAN"),
    Typed  = Table.TransformColumnTypes(Source, {{"TECHNICIAN_KEY", Int64.Type},
                {"HOURLY_RATE_EUR", Currency.Type}, {"HIRE_DATE", type date}}, "en-US"),
    Result = Table.RenameColumns(Typed, {{"TECHNICIAN_KEY", "Technician Key"}, {"TECHNICIAN_ID", "Technician ID"},
                {"TECHNICIAN_NAME", "Technician Name"}, {"HOME_REGION", "Home Region"},
                {"SKILL_LEVEL", "Skill Level"}, {"HOURLY_RATE_EUR", "Hourly Rate"}, {"HIRE_DATE", "Hire Date"},
                {"EMAIL", "Email"}})
in
    Result


// ---------------------------------------------------------------- Failure Code
let
    Source = fnGold("DIM_FAILURE_CODE"),
    Typed  = Table.TransformColumnTypes(Source, {{"FAILURE_KEY", Int64.Type}, {"IS_FAILURE", type logical}}, "en-US"),
    Result = Table.RenameColumns(Typed, {{"FAILURE_KEY", "Failure Key"}, {"FAILURE_CODE", "Failure Code"},
                {"FAILURE_DESCRIPTION", "Failure Description"}, {"FAILURE_CATEGORY", "Failure Category"},
                {"IS_FAILURE", "Is Failure"}})
in
    Result


// ---------------------------------------------------------------- Security Bridge  (hidden, drives RLS)
let
    Source = fnGold("SEC_USER_REGION"),
    Typed  = Table.TransformColumnTypes(Source, {{"USER_PRINCIPAL_NAME", type text}, {"SITE_KEY", Int64.Type}}),
    Lower  = Table.TransformColumns(Typed, {{"USER_PRINCIPAL_NAME", Text.Lower, type text}}),
    Result = Table.RenameColumns(Lower, {{"USER_PRINCIPAL_NAME", "User Principal Name"}, {"SITE_KEY", "Site Key"}})
in
    Result
