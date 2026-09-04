# Data Collector API Retirement – Investigation Results and NSG Flow Logs Migration Runbook

## 1. Purpose

This document describes the investigation performed following the Azure Monitor advisory related to the retirement of the **HTTP Data Collector API**, the legacy network logging components identified in the affected subscription, and the proposed procedure to migrate the existing **NSG Flow Logs to Virtual Network Flow Logs**.

The document also defines:

- Current findings and affected resources.
- Retirement timelines.
- IaC/ownership investigation.
- Migration decision criteria.
- Pre-migration checks.
- Microsoft migration script procedure.
- Validation steps.
- Rollback procedure.
- Post-migration cleanup.

---

## 2. Executive Summary

Azure Service Health reported that the following subscription is currently using the legacy Azure Monitor Data Collector API:

| Item | Value |
|---|---|
| Subscription | **Santander Management - Basefarm CSP** |
| Region investigated | **West Europe** |
| Azure advisory | HTTP Data Collector API retirement |
| Data Collector API support retirement | **14 September 2026** |
| NSG Flow Logs retirement | **30 September 2027** |
| Immediate outage expected on 14/09/2026 | **No** |
| NSG Flow Logs identified | **4** |
| Traffic Analytics | **Enabled** |
| Log Analytics Workspace | `scb-core-mgt-network-log-law` |
| Current migration status | **Analysis completed – no migration changes applied** |

The Data Collector API date of **14 September 2026 is not a hard technical cut-off**. Existing ingestion using TLS 1.2+ is expected to continue working after that date, although the API becomes legacy/out of normal support.

Separately, Microsoft will retire **NSG Flow Logs on 30 September 2027**. Existing NSG Flow Log resources should therefore be migrated to **Virtual Network Flow Logs**.

---

## 3. Important distinction between the two retirements

### HTTP Data Collector API

**Support retirement:** 14 September 2026.

Key points:

- The legacy API reaches support retirement on this date.
- Existing ingestion using TLS 1.2+ is expected to continue.
- The API becomes legacy/out of normal support.
- Migration to the DCR-based Logs Ingestion API is recommended.

> **14 September 2026 should not be treated as an immediate service outage deadline.**

### NSG Flow Logs

**Service retirement:** 30 September 2027.

NSG Flow Logs are a separate Azure Network Watcher feature and have their own retirement lifecycle.

> **NSG Flow Logs should be migrated before 30 September 2027.**

---

## 4. Investigation performed

### 4.1 Log Analytics investigation

All Log Analytics Workspaces within the affected subscription were queried to identify active custom tables.

The following tables were identified as actively receiving data:

```text
AzureNetworkAnalytics_CL
AzureNetworkAnalyticsIPDetails_CL
```

Both were found in:

```text
scb-core-mgt-network-log-law
```

and are shown in Log Analytics as:

```text
Custom table (classic)
```

`AzureNetworkAnalytics_CL` is the legacy Traffic Analytics table used with NSG Flow Logs.

---

## 5. Network Watcher findings

The investigation identified **4 active NSG Flow Logs** in **West Europe**.

All four:

- Are NSG-based Flow Logs.
- Have Traffic Analytics enabled.
- Send data to `scb-core-mgt-network-log-law`.
- Use the existing network logging Storage Account.
- Are candidates for migration to Virtual Network Flow Logs.

| NSG | Subnet | Virtual Network |
|---|---|---|
| `scb-core-mgt-network-build-nsg` | `SCB-CORE-MGT-NETWORK-BUILD-SNET` | `SCB-CORE-MGT-NETWORK-VNET` |
| `scb-core-mgt-network-vm-nsg` | `SCB-CORE-MGT-NETWORK-VM-SNET` | `SCB-CORE-MGT-NETWORK-VNET` |
| `scb-core-mgt-network-vnetintegration-nsg` | `scb-core-mgt-network-vnetintegration-snet` | `SCB-CORE-MGT-NETWORK-VNET` |
| `scb-core-mgt-pe-nsg` | `SCB-CORE-MGT-NETWORK-PE-SNET` | `SCB-CORE-MGT-NETWORK-PE-VNET` |

Current architecture:

```text
NSG
 │
 ▼
NSG Flow Log
 │
 ▼
Azure Storage
 │
 ▼
Traffic Analytics
 │
 ▼
scb-core-mgt-network-log-law
 │
 ├─ AzureNetworkAnalytics_CL
 └─ AzureNetworkAnalyticsIPDetails_CL
```

Target architecture:

```text
VNet / Subnet
 │
 ▼
Virtual Network Flow Log
 │
 ▼
Azure Storage
 │
 ▼
Traffic Analytics
 │
 ▼
scb-core-mgt-network-log-law
 │
 ▼
NTANetAnalytics
```

---

## 6. Important caveat regarding the original advisory

The investigation found legacy `Custom table (classic)` tables associated with the four NSG Flow Logs.

> **This does not by itself prove that these four NSG Flow Logs are the exact component that triggered the Data Collector API Service Health advisory.**

The Data Collector API and NSG Flow Logs have independent retirement timelines.

The current investigation establishes:

1. The subscription received the Data Collector API advisory.
2. Legacy custom tables are actively receiving Network Watcher Traffic Analytics data.
3. Four NSG Flow Logs requiring migration were identified.
4. Their migration should be addressed independently of whether they are ultimately confirmed as the direct cause of the Data Collector API advisory.

---

## 7. IaC / repository investigation

The repository investigated was:

```text
CCoE-scb-tf-main
```

The existing NSGs were found referenced from Terraform using `data` blocks, for example:

```hcl
data "azurerm_network_security_group" "nsg" {
  name                = "scb-core-mgt-network-build-nsg"
  resource_group_name = "scb-core-mgt-network-nsg-rg"
}
```

This means that section of Terraform reads an already existing NSG rather than creating it.

Resource tags on the NSGs include indicators such as:

```text
provisionedwith = terraform
repository      = CCoE-scb-tf-main
```

However, no current Terraform `resource` definition for the **MGT Flow Logs** was located.

The Git history was also reviewed.

An old file was found:

```text
stg/core/network/network-watcher-flow-log.tf
```

but:

- It belonged to **STG**, not MGT.
- The historical `azurerm_network_watcher_flow_log` block reviewed was commented.
- The STG implementation was later removed.
- No equivalent historical `mgt/core/network/network-watcher-flow-log.tf` was found.
- Searching the MGT history for `azurerm_network_watcher_flow_log` returned no result.

### Current conclusion

No evidence has currently been found that the four MGT NSG Flow Logs are directly managed by the Terraform code reviewed.

This **does not prove they were manually created**. They could still be managed by another repository, pipeline, Azure Policy, script or automation.

---

## 8. Migration decision

```text
Are the 4 NSG Flow Logs managed by IaC / Policy / automation?
                     │
             ┌───────┴────────┐
             │                │
            YES               NO
             │                │
             ▼                ▼
   Modify owning IaC      Use Microsoft
   implementation        migration script
             │                │
             └───────┬────────┘
                     ▼
            Validate migration
```

### If managed by IaC

Do **not** migrate them independently with the Microsoft script.

The migration should be implemented through the owning repository/module to avoid infrastructure drift.

### If not managed by IaC

Use Microsoft's official migration script:

```text
MigrationFromNsgToAzureFlowLogging.ps1
```

---

## 9. Migration analysis already completed

The Microsoft migration package was downloaded from:

```text
Network Watcher
   → Migrate flow logs
```

The downloaded package contains:

```text
MigrationFromNsgToAzureFlowLogging.ps1
RegionSubscriptionConfig.json
```

The script was executed using:

```powershell
.\MigrationFromNsgToAzureFlowLogging.ps1
```

and:

```text
1. Run analysis
```

Only the **analysis phase** was executed.

### Result

The analysis correctly detected the 4 existing NSG Flow Logs.

No Azure resources were changed.

The generated HTML report showed:

```text
CanBeAggregated = False
```

for the identified Flow Logs.

The reason reported was that all subnets within the corresponding VNets do not have Flow Logs with identical configuration.

Consequently, the current recommended migration strategy is:

> **Migration without aggregation**

---

## 10. Pre-migration requirements

| Check | Required state |
|---|---|
| Flow Log ownership | Confirmed not managed by another IaC/pipeline/policy |
| Change approval | Approved |
| PowerShell | PowerShell 7 |
| Az PowerShell module | Installed |
| Azure RBAC | Sufficient access to Network Watcher, subscription and Log Analytics |
| Current analysis | Re-run immediately before migration |
| Existing configuration | Recorded |
| Migration HTML report | Saved |
| Script + JSON | Saved |
| Concurrent network changes | None planned |

---

## 11. Migration procedure

### Step 1 – Re-run analysis

```powershell
.\MigrationFromNsgToAzureFlowLogging.ps1
```

Select:

```text
1. Run analysis
```

Enter:

```text
.\RegionSubscriptionConfig.json
```

Confirm that the same **4 NSG Flow Logs** are still detected.

### Step 2 – Review generated HTML report

Review:

- Existing NSG Flow Logs.
- Target resource.
- Storage configuration.
- Traffic Analytics configuration.
- New VNet/Subnet Flow Logs to be created.
- Flow Logs that will be disabled.
- Aggregation eligibility.

### Step 3 – Start migration

The script presents:

```text
1. Re-Run analysis
2. Proceed with migration with aggregation
3. Proceed with migration without aggregation
4. Quit
```

Based on the current analysis, the intended option is:

```text
3. Proceed with migration without aggregation
```

---

## 12. Expected migration result

The script should:

1. Create the corresponding Virtual Network Flow Logs.
2. Preserve the relevant Storage and Traffic Analytics settings.
3. Disable the NSG Flow Logs being replaced.

---

## 13. Validation

### 13.1 Azure Network Watcher

Confirm:

```text
New Virtual Network Flow Logs = Enabled
Old NSG Flow Logs             = Disabled
```

For every new Flow Log validate:

- Correct target VNet/subnet.
- Provisioning state = `Succeeded`.
- Correct Storage Account.
- Traffic Analytics = enabled.
- Correct Log Analytics Workspace.
- Expected processing interval/settings.

### 13.2 Validate Log Analytics

Workspace:

```text
scb-core-mgt-network-log-law
```

Example validation query:

```kusto
NTANetAnalytics
| where TimeGenerated > ago(2h)
| summarize
    Records = count(),
    LastSeen = max(TimeGenerated)
```

Expected result:

```text
Records > 0
LastSeen = recent timestamp
```

### 13.3 Validate Traffic Analytics

Confirm that:

- Recent traffic data continues to appear.
- Expected VNets/subnets are represented.
- No unexpected monitoring gap exists.
- Network traffic visibility remains equivalent to the previous configuration.

---

## 14. Rollback

After migration, the Microsoft script presents a rollback decision.

```text
Do you want to rollback?
You won't get the option to revert the actions done now again (y/n):
```

Interpretation:

```text
y = rollback the migration
n = accept the migration
```

### Rollback criteria

Rollback should be considered if:

- A new Flow Log fails provisioning.
- Expected Traffic Analytics data does not arrive after allowing the normal processing interval.
- New resources target the wrong VNet/subnet.
- Storage configuration differs from the expected configuration.
- Log Analytics ingestion is not working.
- Unexpected network monitoring coverage is observed.
- The migration output differs materially from the approved analysis.

---

## 15. Post-migration cleanup

After successful validation and migration acceptance:

1. Confirm all migrated NSG Flow Logs remain disabled.
2. Record new VNet Flow Log resource names/IDs.
3. Save the final migration report.
4. Update this Confluence page with the migration date.
5. Update the related Azure DevOps/ServiceNow task.
6. Remove legacy NSG Flow Log resources after the agreed observation/change period.
7. Confirm Traffic Analytics remains healthy.

---

## 16. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Unknown IaC ownership | Configuration drift | Confirm ownership before executing script |
| New VNet Flow Log fails | Monitoring gap | Validate before migration acceptance |
| Traffic Analytics ingestion delay | False failure indication | Allow expected processing interval |
| Incorrect migration target | Missing/excess logging | Review analysis report before execution |
| Duplicate logging | Additional Storage/monitoring cost | Ensure old NSG Flow Logs are disabled after validation |
| Insufficient RBAC | Partial/failed execution | Validate permissions before change |
| Concurrent topology change | Unexpected migration behavior | Freeze topology changes during migration |
| Rollback option lost | More complex recovery | Do not accept migration until validation is complete |

The migration primarily affects **network observability/logging**, not NSG security rules, routing or production packet forwarding.

---

## 17. Current status

```text
Data Collector API advisory reviewed          ✅
Affected subscription identified              ✅
Log Analytics workspaces reviewed             ✅
Legacy Traffic Analytics tables identified    ✅
4 NSG Flow Logs identified                    ✅
Microsoft migration analysis executed         ✅
Azure changes applied                         ❌
Migration executed                            ❌
IaC ownership fully confirmed                 ❌
Migration approval received                   ❌
```

### Current action

> **Confirm with the Platform/Network team whether the four MGT NSG Flow Logs are managed by another IaC repository, pipeline, Azure Policy or automation.**

If the answer is **no**, proceed with the Microsoft migration script following this runbook.

If the answer is **yes**, implement the migration using the owning IaC solution instead.

---

## 18. Microsoft references

- HTTP Data Collector API migration guidance:  
  https://learn.microsoft.com/en-us/azure/azure-monitor/logs/custom-logs-migrate

- NSG Flow Logs migration procedure:  
  https://learn.microsoft.com/en-us/azure/network-watcher/nsg-flow-logs-migrate

- Azure network monitoring guidance:  
  https://learn.microsoft.com/en-us/azure/networking/design-guide/monitor

- Traffic Analytics schema documentation:  
  https://learn.microsoft.com/en-us/azure/network-watcher/traffic-analytics-schema
