<#
.SYNOPSIS
    Audit Azure Update Manager Dynamic Scopes.

.DESCRIPTION
    Read-only script.
    Discovers:
      - Maintenance Configurations
      - Dynamic Scope assignments
      - Scope filters
      - Subscription associations
      - VMs potentially affected

    It DOES NOT modify Azure resources.
#>

param (
    [string]$OutputPath = "./UpdateManager-Audit"
)

$ErrorActionPreference = "Continue"

$centralSub = "e76d4c12-0b6b-4a47-a714-fa2302974203"
$centralRG  = "scb-core-mgt-updatemgr-rg"

$targetSchedules = @(
    "Dev 1",
    "Dev 2",
    "Mgt 1",
    "Mgt 2",
    "Prd 1",
    "Prd 2"
)

New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

Write-Host ""
Write-Host "========================================"
Write-Host " Azure Update Manager - Dynamic Scope Audit"
Write-Host "========================================"
Write-Host ""

# ----------------------------------------------------------
# 1. Get subscriptions
# ----------------------------------------------------------

Write-Host "[1/4] Getting subscriptions..."

$subscriptions = az account list `
    --query "[?state=='Enabled'].{Name:name,Id:id}" `
    -o json | ConvertFrom-Json

Write-Host "Found $($subscriptions.Count) accessible subscriptions."
Write-Host ""

# ----------------------------------------------------------
# 2. Get Maintenance Configurations
# ----------------------------------------------------------

Write-Host "[2/4] Getting Maintenance Configurations..."

$query = @"
Resources
| where type =~ 'microsoft.maintenance/maintenanceconfigurations'
| where subscriptionId == '$centralSub'
| where resourceGroup =~ '$centralRG'
| project name, id, subscriptionId, resourceGroup, location,
          maintenanceScope=tostring(properties.maintenanceScope)
"@

$result = az graph query `
    -q $query `
    --first 1000 `
    -o json | ConvertFrom-Json

$configurations = $result.data

$targetConfigs = @()

foreach ($config in $configurations) {

    foreach ($schedule in $targetSchedules) {

        if ($config.name -like "$schedule -*") {

            $targetConfigs += $config
            break
        }
    }
}

Write-Host "Relevant Maintenance Configurations:"
$targetConfigs |
    Select-Object name |
    Format-Table -AutoSize

# ----------------------------------------------------------
# 3. Scan subscription assignments
# ----------------------------------------------------------

Write-Host ""
Write-Host "[3/4] Scanning Dynamic Scope assignments..."
Write-Host ""

$allAssignments = @()

$total = $subscriptions.Count
$current = 0

foreach ($sub in $subscriptions) {

    $current++

    Write-Host "[$current/$total] $($sub.Name)"

    try {

        $raw = az maintenance assignment list-subscription `
            --subscription $sub.Id `
            -o json `
            --only-show-errors 2>$null

        if (-not $raw) {

            Write-Host "        No assignments returned."
            continue
        }

        $assignments = $raw | ConvertFrom-Json

        if ($assignments.Count -eq 0) {

            Write-Host "        No assignments."
            continue
        }

        Write-Host "        Found $($assignments.Count) assignment(s)."

        foreach ($assignment in $assignments) {

            # Only interested in our six Maintenance Configurations

            $matchingConfig = $targetConfigs |
                Where-Object {
                    $_.id -eq $assignment.maintenanceConfigurationId
                }

            if (-not $matchingConfig) {
                continue
            }

            $filter = $assignment.filter

            $allAssignments += [PSCustomObject]@{

                SubscriptionName = $sub.Name

                SubscriptionId = $sub.Id

                AssignmentName = $assignment.name

                MaintenanceConfiguration =
                    $matchingConfig.name

                Locations =
                    if ($filter.locations) {
                        $filter.locations -join ";"
                    } else {
                        ""
                    }

                ResourceGroups =
                    if ($filter.resourceGroups) {
                        $filter.resourceGroups -join ";"
                    } else {
                        ""
                    }

                ResourceTypes =
                    if ($filter.resourceTypes) {
                        $filter.resourceTypes -join ";"
                    } else {
                        ""
                    }

                OsTypes =
                    if ($filter.osTypes) {
                        $filter.osTypes -join ";"
                    } else {
                        ""
                    }

                TagOperator =
                    if ($filter.tagSettings) {
                        $filter.tagSettings.filterOperator
                    } else {
                        ""
                    }

                Tags =
                    if ($filter.tagSettings.tags) {
                        $filter.tagSettings.tags |
                            ConvertTo-Json -Compress -Depth 10
                    } else {
                        ""
                    }

                AssignmentId =
                    $assignment.id
            }
        }
    }
    catch {

        Write-Warning "        Failed: $($_.Exception.Message)"
    }
}

# ----------------------------------------------------------
# 4. Results
# ----------------------------------------------------------

Write-Host ""
Write-Host "[4/4] Results"
Write-Host ""

if ($allAssignments.Count -eq 0) {

    Write-Warning "No matching Dynamic Scope assignments found."

}
else {

    $allAssignments |
        Sort-Object SubscriptionName, MaintenanceConfiguration |
        Format-Table `
            SubscriptionName,
            MaintenanceConfiguration,
            Locations,
            OsTypes,
            TagOperator,
            Tags `
            -AutoSize

    $csv = Join-Path $OutputPath "dynamic-scopes.csv"

    $allAssignments |
        Sort-Object SubscriptionName, MaintenanceConfiguration |
        Export-Csv `
            $csv `
            -NoTypeInformation `
            -Encoding UTF8

    Write-Host ""
    Write-Host "CSV generated:"
    Write-Host $csv
}

Write-Host ""
Write-Host "========================================"
Write-Host " Audit finished"
Write-Host " No Azure resources were modified."
Write-Host "========================================"
