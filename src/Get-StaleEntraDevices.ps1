#Requires -Version 5.1
<#
.SYNOPSIS
    List Entra ID devices with ApproximateLastSignInDateTime older than N days.
.DESCRIPTION
    Exports a CSV of stale devices. Optionally disables them when -DisableStale is
    passed with -Confirm or -Force. Disable defaults to -WhatIf unless you explicitly
    set -WhatIf:$false after confirming.
.PARAMETER DaysInactive
    Devices whose ApproximateLastSignInDateTime is older than this many days (default 90).
.PARAMETER ExportPath
    CSV path. Defaults to .\out\stale-devices-<date>.csv
.PARAMETER DisableStale
    When set, attempt to disable matching devices (requires Device.ReadWrite.All).
.PARAMETER Force
    Skip interactive confirmation when disabling.
.EXAMPLE
    .\Get-StaleEntraDevices.ps1 -DaysInactive 90
.EXAMPLE
    .\Get-StaleEntraDevices.ps1 -DaysInactive 180 -DisableStale -WhatIf
.NOTES
    Permissions: Device.Read.All (list); Device.ReadWrite.All (disable).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 90,

    [string]$ExportPath,

    [switch]$DisableStale,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

Connect-HelpdeskGraph | Out-Null

$cutoff = (Get-Date).ToUniversalTime().AddDays(-$DaysInactive)
Write-HelpdeskLog -Level INFO -Message "Cutoff (UTC): $($cutoff.ToString('o')) ($DaysInactive days)"

if (-not $ExportPath) {
    $outDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'out'
    if (-not (Test-Path -LiteralPath $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    $ExportPath = Join-Path $outDir ("stale-devices-{0:yyyy-MM-dd}.csv" -f (Get-Date))
}

$devices = Invoke-HelpdeskGraphAction -ActionName 'Get-MgDevice' -ScriptBlock {
    Get-MgDevice -All -Property 'id,displayName,approximateLastSignInDateTime,accountEnabled,operatingSystem,deviceId' `
        -ErrorAction Stop
}

$stale = foreach ($d in $devices) {
    $last = $d.ApproximateLastSignInDateTime
    if (-not $last) {
        # No sign-in timestamp — treat as stale candidate but flag it
        [pscustomobject]@{
            DeviceObjectId                 = $d.Id
            DeviceId                       = $d.DeviceId
            DisplayName                    = $d.DisplayName
            OperatingSystem                = $d.OperatingSystem
            ApproximateLastSignInDateTime  = $null
            AccountEnabled                 = $d.AccountEnabled
            StaleReason                    = 'NoApproximateLastSignInDateTime'
        }
        continue
    }
    $lastUtc = [datetime]::Parse($last.ToString()).ToUniversalTime()
    if ($lastUtc -lt $cutoff) {
        [pscustomobject]@{
            DeviceObjectId                 = $d.Id
            DeviceId                       = $d.DeviceId
            DisplayName                    = $d.DisplayName
            OperatingSystem                = $d.OperatingSystem
            ApproximateLastSignInDateTime  = $lastUtc.ToString('o')
            AccountEnabled                 = $d.AccountEnabled
            StaleReason                    = "OlderThan${DaysInactive}Days"
        }
    }
}

$staleList = @($stale)
Write-HelpdeskLog -Level INFO -Message "Stale device count: $($staleList.Count)"
$staleList | Sort-Object ApproximateLastSignInDateTime | Format-Table -AutoSize
$staleList | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8
Write-HelpdeskLog -Level INFO -Message "Exported: $ExportPath"

if ($DisableStale) {
    foreach ($item in $staleList) {
        if (-not $item.AccountEnabled) { continue }
        $target = "{0} ({1})" -f $item.DisplayName, $item.DeviceObjectId
        if ($Force -or $PSCmdlet.ShouldProcess($target, 'Disable Entra device (AccountEnabled=false)')) {
            Invoke-HelpdeskGraphAction -ActionName 'Update-MgDevice-Disable' -ScriptBlock {
                Update-MgDevice -DeviceId $item.DeviceObjectId -AccountEnabled:$false -ErrorAction Stop
            }
            Write-HelpdeskLog -Level AUDIT -Message "Disabled device $target" -Properties @{
                DeviceObjectId = $item.DeviceObjectId
                DisplayName    = $item.DisplayName
            }
        }
    }
}
else {
    Write-HelpdeskLog -Level INFO -Message "Disable skipped (pass -DisableStale with -Confirm/-Force to mutate)."
}
