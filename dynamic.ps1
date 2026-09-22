#requires -Version 5.1
<#
.SYNOPSIS
Read-only Azure Update Manager configuration and Dynamic Scope audit.
.DESCRIPTION
Requires Azure CLI, an authenticated session, maintenance and resource-graph extensions.
Version 2: discovers subscription-level assignments through Resource Graph.
Resource Graph results reflect indexed resources visible to the signed-in identity.
Does not modify Azure resources or switch the active subscription.
Writes local reports and raw JSON. Does not evaluate VM membership.
Each invocation creates a separate output directory.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = './UpdateManager-Audit',
    [string]$CentralSubscriptionId = 'e76d4c12-0b6b-4a47-a714-fa2302974203',
    [string]$CentralResourceGroup = 'scb-core-mgt-updatemgr-rg',
    [string[]]$TargetSchedules = @('Dev 1','Dev 2','Mgt 1','Mgt 2','Prd 1','Prd 2'),
    [string[]]$SubscriptionIds = @(),
    [switch]$AllConfigurations
)

$ErrorActionPreference = 'Stop'
# Native exit codes are checked explicitly, including in newer PowerShell.
$PSNativeCommandUseErrorActionPreference = $false
$runName = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0,8))
$runPath = Join-Path $OutputPath $runName
$null = New-Item -ItemType Directory -Path $runPath -Force
$runPath = (Resolve-Path -LiteralPath $runPath).Path

function Invoke-AzJson {
    param([string[]]$Arguments, [string]$Label)
    $jsonPath = Join-Path $runPath "$Label.json"
    $errorPath = Join-Path $runPath "$Label.stderr.txt"
    Write-Host "  Query: $Label (waiting for Azure CLI...)"
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = & az @Arguments --output json --only-show-errors 2> $errorPath
    $code = $LASTEXITCODE
    $watch.Stop()
    Write-Host ('  Completed in {0:N1}s; exit code {1}' -f $watch.Elapsed.TotalSeconds, $code)
    $rawText = $raw -join [Environment]::NewLine
    $rawText | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    if ($code -ne 0) {
        $details = Get-Content -LiteralPath $errorPath -Raw -ErrorAction SilentlyContinue
        throw "Azure CLI failed ($code): $Label. $details"
    }
    if ([string]::IsNullOrWhiteSpace($rawText)) {
        throw "Azure CLI returned no JSON: $Label. This is NOT a confirmed empty result."
    }
    # PowerShell enumerates empty JSON arrays into no pipeline output.
    if ($rawText.Trim() -match '^\[\s*\]$') { return }
    $parsed = ConvertFrom-Json -InputObject $rawText -ErrorAction Stop
    if ($null -eq $parsed) { throw "Azure CLI returned JSON null: $Label." }
    if ($parsed.PSObject.Properties['error']) {
        throw "Azure returned an error: $($parsed.error | ConvertTo-Json -Compress -Depth 20)"
    }
    return $parsed
}

function Get-Items {
    param($Response)
    if ($null -eq $Response) { return }
    if ($Response.PSObject.Properties['value']) {
        if ($Response.nextLink) {
            throw 'Response contains nextLink: refusing to report a partial list as complete. Inspect the raw JSON.'
        }
        return $Response.value
    }
    return $Response
}

function Get-PropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.properties -and $Object.properties.PSObject.Properties[$Name]) {
        return $Object.properties.$Name
    }
    return $Object.$Name
}

function Normalize-Id {
    param([string]$Id)
    if ([string]::IsNullOrWhiteSpace($Id)) { return '' }
    return $Id.Trim().TrimEnd('/').ToLowerInvariant()
}

function Get-GraphAssignments {
    param([string]$SubscriptionId)
    # Keep id and avoid take/limit so Resource Graph can return a continuation token.
    $query = @'
maintenanceresources
| where type =~ 'microsoft.maintenance/configurationassignments'
| where id matches regex @'(?i)^/subscriptions/[^/]+/providers/microsoft\.maintenance/configurationassignments/[^/]+/?$'
| project id, name, subscriptionId, properties
| order by id asc
'@
    $buffer = [System.Collections.Generic.List[object]]::new()
    $seenIds = @{}
    $seenTokens = @{}
    $token = ''
    $page = 0
    do {
        $page++
        $cliArgs = @('graph','query','-q',$query,'--subscriptions',$SubscriptionId,'--first','1000')
        if ($token) { $cliArgs += @('--skip-token',$token) }
        $response = Invoke-AzJson -Arguments $cliArgs -Label "assignments-$SubscriptionId-page-$page"
        if (-not $response.PSObject.Properties['data']) {
            throw 'Resource Graph response has no data property. Inspect the saved JSON.'
        }
        $items = @($response.data | Where-Object { $null -ne $_ })
        foreach ($item in $items) {
            $idKey = Normalize-Id $item.id
            if (-not $idKey) { throw 'Resource Graph returned an assignment without id.' }
            if ($item.subscriptionId -ine $SubscriptionId) { throw 'Resource Graph returned an unexpected subscription.' }
            if ($seenIds.ContainsKey($idKey)) {
                throw 'Duplicate assignment across pages; inventory may have changed. Rerun the audit.'
            }
            $seenIds[$idKey] = $true
            $buffer.Add($item)
        }
        $token = [string]$response.skip_token
        if (-not $token) { $token = [string]$response.'$skipToken' }
        Write-Host "  Graph page $page : $($items.Count) scope(s); accumulated: $($buffer.Count)"
        if ($token) {
            if ($items.Count -eq 0 -or $seenTokens.ContainsKey($token)) {
                throw 'Resource Graph pagination did not advance. Inspect saved pages.'
            }
            $seenTokens[$token] = $true
        } else {
            $total = $response.total_records
            if ($null -eq $total) { $total = $response.totalRecords }
            if (($null -ne $total -and [long]$total -gt $buffer.Count) -or
                ([string]$response.resultTruncated -ieq 'true') -or
                ([string]$response.result_truncated -ieq 'true')) {
                throw 'Resource Graph results are incomplete and no continuation token was returned.'
            }
        }
    } while ($token)
    # Emit only after every page succeeded; failed scans cannot look complete.
    return $buffer.ToArray()
}

Write-Host "Azure Update Manager audit v2 - Resource Graph - READ ONLY"
Write-Host "Reports: $runPath"
try {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) is not installed or not in PATH.' }
    $extensions = @(Get-Items (Invoke-AzJson -Arguments @('extension','list') -Label 'extensions'))
    if (-not ($extensions | Where-Object { $_.name -eq 'maintenance' })) {
        throw 'Install the CLI extension first: az extension add --name maintenance'
    }
    if (-not ($extensions | Where-Object { $_.name -eq 'resource-graph' })) {
        throw 'Install the CLI extension first: az extension add --name resource-graph'
    }

    Write-Host '[1/4] Reading accessible subscriptions'
    $accountResponse = Invoke-AzJson -Arguments @('account','list') -Label 'subscriptions'
    $subscriptions = @(Get-Items $accountResponse | Where-Object { $_.state -eq 'Enabled' })
    if ($SubscriptionIds.Count -gt 0) {
        foreach ($requested in $SubscriptionIds) {
            if (-not ($subscriptions | Where-Object { $_.id -eq $requested })) {
                throw "Subscription $requested is not in the enabled accessible subscription list. Check login/tenant/access."
            }
        }
        $subscriptions = @($subscriptions | Where-Object { $_.id -in $SubscriptionIds })
    }
    if ($subscriptions.Count -eq 0) { throw 'No enabled subscriptions available. Check az login and tenant.' }
    Write-Host "Subscriptions to scan: $($subscriptions.Count)"

    Write-Host '[2/4] Reading Maintenance Configurations directly (without Resource Graph)'
    $configArgs = @('maintenance','configuration','list','--subscription',$CentralSubscriptionId,'--resource-group',$CentralResourceGroup)
    $configurations = @(Get-Items (Invoke-AzJson -Arguments $configArgs -Label 'configurations'))
    $configurations | Select-Object name,id | Format-Table -AutoSize | Out-Host
    $targetConfigs = @($configurations | Where-Object {
        $configName = [string]$_.name
        $include = [bool]$AllConfigurations
        foreach ($schedule in $TargetSchedules) {
            # Exact schedule or schedule followed by a hyphen/dash and suffix.
            $pattern = '^' + [regex]::Escape($schedule.Trim()) + '(?:\s*[-\u2013\u2014].*)?$'
            if ($configName -match $pattern) { $include = $true }
        }
        $include
    })
    Write-Host "Configurations returned: $($configurations.Count); matched: $($targetConfigs.Count)"
    if ($targetConfigs.Count -eq 0) {
        throw 'No configuration names matched. Check configurations.json and TargetSchedules, or use -AllConfigurations to audit the whole central resource group.'
    }
    $configIndex = @{}
    foreach ($config in $targetConfigs) { $configIndex[(Normalize-Id $config.id)] = $config.name }
    $targetConfigs | Select-Object name,id | Export-Csv -LiteralPath (Join-Path $runPath 'target-configurations.csv') -NoTypeInformation -Encoding UTF8

    $rows = [System.Collections.Generic.List[object]]::new()
    $status = [System.Collections.Generic.List[object]]::new()
    Write-Host '[3/4] Reading Dynamic Scopes via Resource Graph (all pages per subscription)'
    $current = 0
    foreach ($sub in $subscriptions) {
        $current++
        Write-Host "[$current/$($subscriptions.Count)] $($sub.name) ($($sub.id))"
        $found = 0
        $matched = 0
        $invalid = 0
        try {
            $assignments = @(Get-GraphAssignments -SubscriptionId $sub.id)
            $found = $assignments.Count
            foreach ($assignment in $assignments) {
                $configId = [string](Get-PropertyValue $assignment 'maintenanceConfigurationId')
                $filter = Get-PropertyValue $assignment 'filter'
                $key = Normalize-Id $configId
                if (-not $key) { $invalid++ }
                $isTarget = $key -and $configIndex.ContainsKey($key)
                # Distinguish subscription-level scopes from direct resource assignments.
                $isDynamic = [string]$assignment.id -match '^/subscriptions/[^/]+/providers/Microsoft\.Maintenance/configurationAssignments/[^/]+/?$'
                if ($isTarget -and $isDynamic) { $matched++ }
                $rows.Add([PSCustomObject]@{
                    SubscriptionName = $sub.name
                    SubscriptionId = $sub.id
                    AssignmentName = $assignment.name
                    IsSubscriptionScope = [bool]$isDynamic
                    MatchesTarget = [bool]$isTarget
                    MaintenanceConfiguration = $(if ($isTarget) { $configIndex[$key] } else { '' })
                    MaintenanceConfigurationId = $configId
                    Locations = @($filter.locations) -join ';'
                    ResourceGroups = @($filter.resourceGroups) -join ';'
                    ResourceTypes = @($filter.resourceTypes) -join ';'
                    ResourceIds = @($filter.resourceIds) -join ';'
                    AvailabilityZones = @($filter.availabilityZones) -join ';'
                    OsTypes = @($filter.osTypes) -join ';'
                    TagOperator = $filter.tagSettings.filterOperator
                    Tags = $(if ($null -ne $filter.tagSettings.tags) { ConvertTo-Json -InputObject $filter.tagSettings.tags -Compress -Depth 30 } else { '' })
                    FilterPresent = ($null -ne $filter)
                    FilterJson = $(if ($null -ne $filter) { ConvertTo-Json -InputObject $filter -Compress -Depth 40 } else { '' })
                    AssignmentId = $assignment.id
                })
            }
            $state = if ($invalid -gt 0) { 'ReviewSchema' } else { 'OK' }
            $status.Add([PSCustomObject]@{ SubscriptionName=$sub.name; SubscriptionId=$sub.id; Status=$state; Returned=$found; MatchingDynamicScopes=$matched; MissingConfigurationId=$invalid; Error='' })
            Write-Host "  Returned: $found; matching subscription scopes: $matched; missing config ID: $invalid"
        }
        catch {
            $status.Add([PSCustomObject]@{ SubscriptionName=$sub.name; SubscriptionId=$sub.id; Status='Failed'; Returned=$found; MatchingDynamicScopes=$matched; MissingConfigurationId=$invalid; Error=$_.Exception.Message })
            Write-Warning $_.Exception.Message
        }
        # Keep progress on disk even if the run is interrupted later.
        $status | Export-Csv -LiteralPath (Join-Path $runPath 'subscription-status.csv') -NoTypeInformation -Encoding UTF8
    }

    Write-Host '[4/4] Reports'
    $status | Export-Csv -LiteralPath (Join-Path $runPath 'subscription-status.csv') -NoTypeInformation -Encoding UTF8
    $status | Format-Table SubscriptionName,Status,Returned,MatchingDynamicScopes -AutoSize | Out-Host
    if ($rows.Count -gt 0) {
        $rows | Export-Csv -LiteralPath (Join-Path $runPath 'all-assignments.csv') -NoTypeInformation -Encoding UTF8
    }
    $matches = @($rows | Where-Object { $_.MatchesTarget -and $_.IsSubscriptionScope })
    if ($matches.Count -gt 0) {
        $matches | Sort-Object SubscriptionName,MaintenanceConfiguration | Export-Csv -LiteralPath (Join-Path $runPath 'dynamic-scopes.csv') -NoTypeInformation -Encoding UTF8
        $matches | Format-Table SubscriptionName,MaintenanceConfiguration,AssignmentName -AutoSize | Out-Host
    } else {
        Write-Warning 'No matching subscription scopes returned. Inspect status, raw JSON and all-assignments.csv; this does not prove no scopes exist.'
    }
    $issues = @($status | Where-Object { $_.Status -ne 'OK' }).Count
    if ($issues -gt 0) { Write-Warning "Audit incomplete or needs review: $issues subscription(s). See subscription-status.csv and stderr files." }
    Write-Host "Matching dynamic scopes: $($matches.Count). Reports: $runPath"
    Write-Host 'No Azure resources modified. VM membership was NOT evaluated.'
    Write-Host 'Coverage is limited to indexed resources visible to this identity. An empty Graph response is not proof that no scopes exist.'
}
catch {
    $_.Exception.Message | Set-Content -LiteralPath (Join-Path $runPath 'fatal-error.txt') -Encoding UTF8
    Write-Warning "Audit stopped. Diagnostics: $runPath"
    throw
}
