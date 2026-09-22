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
    [string]$OutputPath = ".\UpdateManager-Audit"
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Functions
# ------------------------------------------------------------

function Write-Section {
    param([string]$Message)

    Write-Host ""
    Write-Host "============================================================"
    Write-Host $Message
    Write-Host "============================================================"
}

# ------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------

Write-Section "Checking Azure connection"

$account = az account show 2>$null | ConvertFrom-Json

if (-not $account) {
    throw "Not logged into Azure. Run 'az login' first."
}

Write-Host "Tenant       : $($account.tenantId)"
Write-Host "Subscription : $($account.name)"
Write-Host "ID           : $($account.id)"

if (-not (Test-Path $OutputPath)) {
    New-Item `
        -ItemType Directory `
        -Path $OutputPath `
        -Force | Out-Null
}

# ------------------------------------------------------------
# Get accessible subscriptions
# ------------------------------------------------------------

Write-Section "Getting accessible subscriptions"

$subscriptions = az account list `
    --query "[?state=='Enabled'].{Name:name,Id:id}" `
    -o json | ConvertFrom-Json

$subscriptions |
    Format-Table Name, Id -AutoSize

$subscriptions |
    Export-Csv `
        "$OutputPath\subscriptions.csv" `
        -NoTypeInformation

# ------------------------------------------------------------
# Maintenance Configurations
# ------------------------------------------------------------

Write-Section "Discovering Maintenance Configurations"

$maintenanceConfigs = @()

foreach ($sub in $subscriptions) {

    Write-Host "Scanning: $($sub.Name)"

    $url = "/subscriptions/$($sub.Id)/providers/Microsoft.Maintenance/maintenanceConfigurations?api-version=2023-04-01"

    try {

        $result = az rest `
            --method GET `
            --url $url `
            -o json | ConvertFrom-Json

        foreach ($config in $result.value) {

            $maintenanceConfigs += [PSCustomObject]@{
                SubscriptionName = $sub.Name
                SubscriptionId   = $sub.Id
                Name             = $config.name
                ResourceGroup    = ($config.id -split "/")[4]
                Location         = $config.location
                MaintenanceScope = $config.properties.maintenanceScope
                Id               = $config.id
            }
        }

    }
    catch {
        Write-Warning "Unable to read Maintenance Configurations from $($sub.Name)"
    }
}

$maintenanceConfigs |
    Format-Table `
        SubscriptionName,
        Name,
        ResourceGroup,
        MaintenanceScope `
        -AutoSize

$maintenanceConfigs |
    Export-Csv `
        "$OutputPath\maintenance-configurations.csv" `
        -NoTypeInformation

# ------------------------------------------------------------
# Dynamic Scope assignments - Azure Resource Graph
# ------------------------------------------------------------

Write-Section "Discovering Dynamic Scope assignments"

$assignments = @()

foreach ($sub in $subscriptions) {

    Write-Host "Scanning assignments: $($sub.Name)"

    $query = @"
Resources
| where type =~ 'microsoft.maintenance/configurationassignments'
| project
    id,
    name,
    subscriptionId,
    location,
    maintenanceConfigurationId = tostring(properties.maintenanceConfigurationId),
    resourceId = tostring(properties.resourceId),
    filter = properties.filter
"@

    try {

        $result = az graph query `
            -q $query `
            --subscriptions $sub.Id `
            --first 1000 `
            -o json | ConvertFrom-Json

        foreach ($assignment in $result.data) {

            $filter = $assignment.filter

            $assignments += [PSCustomObject]@{

                SubscriptionName = $sub.Name
                SubscriptionId   = $sub.Id
                AssignmentName   = $assignment.name

                MaintenanceConfigurationId =
                    $assignment.maintenanceConfigurationId

                Locations =
                    ($filter.locations -join ",")

                ResourceGroups =
                    ($filter.resourceGroups -join ",")

                ResourceTypes =
                    ($filter.resourceTypes -join ",")

                OsTypes =
                    ($filter.osTypes -join ",")

                TagOperator =
                    $filter.tagSettings.filterOperator

                Tags =
                    if ($filter.tagSettings.tags) {
                        $filter.tagSettings.tags |
                            ConvertTo-Json -Compress -Depth 10
                    }
                    else {
                        ""
                    }

                AssignmentId = $assignment.id
            }
        }
    }
    catch {

        Write-Warning "Unable to query assignments from $($sub.Name): $($_.Exception.Message)"
    }
}

# ------------------------------------------------------------
# Display results
# ------------------------------------------------------------

Write-Section "Dynamic Scopes"

$assignments |
    Format-Table `
        SubscriptionName,
        AssignmentName,
        ResourceGroups,
        Locations,
        OsTypes,
        Tags `
        -AutoSize

$assignments |
    Export-Csv `
        "$OutputPath\dynamic-scopes.csv" `
        -NoTypeInformation

# ------------------------------------------------------------
# Search for Bifrost
# ------------------------------------------------------------

Write-Section "Searching for Bifrost VM"

$bifrostQuery = @"
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| where name =~ 'conp1weugvml-bifrost-001'
| project
    name,
    subscriptionId,
    resourceGroup,
    location,
    tags,
    id
"@

try {

    $bifrost = az graph query `
        -q $bifrostQuery `
        --first 1000 `
        -o json |
        ConvertFrom-Json

    if ($bifrost.data.Count -eq 0) {

        Write-Warning "Bifrost VM not found."

    }
    else {

        Write-Host ""
        Write-Host "Bifrost VM found:"
        Write-Host ""

        $bifrost.data |
            Format-List

        $bifrost.data |
            Select-Object `
                name,
                subscriptionId,
                resourceGroup,
                location,
                @{N="Tags";E={
                    $_.tags | ConvertTo-Json -Compress
                }},
                id |
            Export-Csv `
                "$OutputPath\bifrost.csv" `
                -NoTypeInformation
    }

}
catch {

    Write-Warning `
        "Unable to query Resource Graph. Check that the resource-graph extension is available."

}

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

Write-Section "Audit completed"

Write-Host "Output directory:"
Write-Host (Resolve-Path $OutputPath)

Write-Host ""
Write-Host "Generated files:"
Write-Host " - subscriptions.csv"
Write-Host " - maintenance-configurations.csv"
Write-Host " - dynamic-scopes.csv"
Write-Host " - bifrost.csv (if VM found)"
Write-Host ""
Write-Host "NO Azure resources were modified."
