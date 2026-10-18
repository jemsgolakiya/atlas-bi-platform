# Asset Master Data app · Power Fx source

Canvas app (tablet + phone layout) for technicians and Asset Management to **create, read, update and deactivate** asset master data with a full audit trail.
Back-end: Azure SQL (`sql/azure-sql/master_data_crud_audit.sql`) via the SQL Server connector with Entra ID auth. The app **never writes to tables** — every change goes through a stored procedure that validates, versions and (for critical fields) routes to approval.

```
┌─────────────── scrBrowse ───────────────┐   ┌──────────── scrEdit ─────────────┐   ┌──────── scrHistory ────────┐
│ 🔍 search  [Site ▼] [Type ▼] [Crit ▼]   │──►│ form (validated)                 │──►│ audit trail timeline        │
│ gallery: name · site · crit badge ·     │   │ Change reason* (min 10 chars)    │   │ who · when · what · why     │
│ "pending approval" chip                 │   │ [Save]  [Deactivate…]            │   │ (temporal history)          │
│ (+) New asset                           │   │ critical change → approval note  │   └────────────────────────────┘
└─────────────────────────────────────────┘   └──────────────────────────────────┘
```

---

## App.Formulas (named formulas – declarative, recalculated automatically)

```powerfx
// Who is using the app (UPN is written to ChangedBy for the audit trail)
CurrentUserUpn = Lower(User().Email);

// Role from Entra ID group membership (Office365Groups connector). Drives what the UI allows.
IsAssetManager = !IsBlank(
    LookUp(Office365Groups.ListGroupMembers("<sg-atlas-asset-managers-id>").value, Lower(mail) = CurrentUserUpn)
);

// Lookups
Criticalities = '[md].[Criticality]';
AssetTypes   = ["Transformer", "Pump", "Compressor", "HVAC Unit", "Conveyor", "Switchgear"];

// Theme tokens (aligned with the Power BI theme)
ClrPrimary = ColorValue("#1F4E79");
ClrDanger  = ColorValue("#C0392B");
ClrWarning = ColorValue("#D68910");
ClrOk      = ColorValue("#1E8449");
```

## App.OnStart (only what must be imperative)

```powerfx
Set(gblEnvironment, If(Param("env") = "", "PROD", Param("env")));
ClearCollect(colPending,
    Filter('[md].[AssetChangeRequest]', Status = "Pending")
);
```

---

## scrBrowse

**galAssets.Items** – delegable filter (SQL connector delegates `StartsWith`, `=`, `&&`), so it scales to 100k assets:

```powerfx
SortByColumns(
    Filter(
        '[md].[vAsset]',
        IsActive = true,
        StartsWith(AssetName, txtSearch.Text) || StartsWith(AssetId, txtSearch.Text),
        IsBlank(drpSite.Selected.Value)  || SiteId = drpSite.Selected.Value,
        IsBlank(drpType.Selected.Value)  || AssetType = drpType.Selected.Value,
        IsBlank(drpCrit.Selected.Value)  || Criticality = drpCrit.Selected.Value
    ),
    "AssetName", SortOrder.Ascending
)
```

**Criticality badge** `lblCrit.Fill`:

```powerfx
Switch(ThisItem.Criticality, "A", ClrDanger, "B", ClrWarning, ClrOk)
```

**Pending-approval chip** `icoPending.Visible`:

```powerfx
!IsBlank(LookUp(colPending, AssetId = ThisItem.AssetId))
```

**btnNew.OnSelect**

```powerfx
Set(gblMode, "New"); Set(gblAsset, Blank()); Navigate(scrEdit, ScreenTransition.Cover)
```

**galAssets.OnSelect**

```powerfx
Set(gblMode, "Edit"); Set(gblAsset, ThisItem); Navigate(scrEdit, ScreenTransition.Cover)
```

---

## scrEdit

Inputs are plain controls (not an Edit form), because saving goes through a stored procedure.

**Validation** – `btnSave.DisplayMode`:

```powerfx
If(
    And(
        Len(Trim(txtName.Text)) >= 3,
        !IsBlank(drpType.Selected.Value),
        !IsBlank(drpSiteEdit.Selected.Value),
        IsNumeric(txtInstallYear.Text), Value(txtInstallYear.Text) >= 1950, Value(txtInstallYear.Text) <= Year(Today()),
        IsNumeric(txtValue.Text), Value(txtValue.Text) > 0,
        Len(Trim(txtReason.Text)) >= 10,          // mandatory change reason (audit)
        gblMode = "New" || IsAssetManager || gblAsset.Criticality = drpCritEdit.Selected.Code
    ),
    DisplayMode.Edit,
    DisplayMode.Disabled
)
```

**Inline hint** `lblCriticalHint.Text`:

```powerfx
If(
    gblMode = "Edit" && (drpCritEdit.Selected.Code <> gblAsset.Criticality || drpSiteEdit.Selected.Value <> gblAsset.SiteId),
    "⚠ Criticality / site changes need approval by a second Asset Manager (4-eyes principle).",
    ""
)
```

**btnSave.OnSelect** – call the stored procedure, handle concurrency & errors, refresh:

```powerfx
IfError(
    '[md].[usp_Asset_Upsert]'.Run(
        If(gblMode = "New",
           "A" & Text(Value(Mid(First(Sort('[md].[vAsset]', AssetId, SortOrder.Descending)).AssetId, 2)) + 1, "0000"),
           gblAsset.AssetId),
        Trim(txtName.Text),
        drpType.Selected.Value,
        Trim(txtManufacturer.Text),
        Value(txtInstallYear.Text),
        drpCritEdit.Selected.Code,
        drpSiteEdit.Selected.Value,
        Value(txtValue.Text),
        CurrentUserUpn,
        Trim(txtReason.Text),
        If(gblMode = "Edit", gblAsset.RowVersion)          // optimistic concurrency
    );
    Notify(
        If(IsBlank(lblCriticalHint.Text), "Saved. Change is logged in the audit trail.",
           "Saved. Critical change sent for approval."),
        NotificationType.Success
    );
    Refresh('[md].[vAsset]');
    ClearCollect(colPending, Filter('[md].[AssetChangeRequest]', Status = "Pending"));
    Navigate(scrBrowse, ScreenTransition.UnCover),

    // error branch: show the business message thrown by the procedure (e.g. 50002 concurrency)
    Notify("Not saved: " & FirstError.Message, NotificationType.Error)
)
```

> Production note: new IDs come from a SQL `SEQUENCE` inside the procedure; the client-side ID above keeps the demo self-contained.

**btnDeactivate.OnSelect** (visible only for `IsAssetManager`), with confirmation dialog `conDeactivate`:

```powerfx
'[md].[usp_Asset_Deactivate]'.Run(gblAsset.AssetId, CurrentUserUpn, Trim(txtReason.Text));
Notify("Deactivation requested – waiting for approval.", NotificationType.Information);
Navigate(scrBrowse)
```

---

## scrHistory (audit trail)

**galHistory.Items** – temporal history straight from SQL:

```powerfx
SortByColumns(
    Filter('[md].[vAssetAuditTrail]', AssetId = gblAsset.AssetId),
    "ChangedAtUtc", SortOrder.Descending
)
```

**lblHistory.Text**

```powerfx
Text(DateAdd(ThisItem.ChangedAtUtc, -TimeZoneOffset(), TimeUnit.Minutes), "dd.mm.yyyy hh:mm") &
" · " & ThisItem.ChangedBy & Char(10) &
"Criticality " & ThisItem.Criticality & " · Site " & ThisItem.SiteId &
" · Value " & Text(ThisItem.ReplacementValueEur, "#,##0 €") & Char(10) &
"Reason: " & ThisItem.ChangeReason
```

---

## Accessibility & UX standards applied

* All interactive controls have `AccessibleLabel`; tab order follows visual order; minimum touch target 44 px (gloves on site).
* Colour is never the only signal (badge shows the letter A/B/C).
* Works offline-tolerant on the phone layout: search + read; writes require connectivity and say so.
