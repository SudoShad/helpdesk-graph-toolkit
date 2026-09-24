#Requires -Version 5.1
<#
.SYNOPSIS
    Daily helpdesk triage export: stale devices, disabled licensed users, optional risk signals.
.DESCRIPTION
    Writes a dated CSV under ./out/. Risk events are included only when
    IdentityRiskEvent.Read.All (or equivalent) is granted; otherwise that section
    is skipped with a warning.
.PARAMETER DaysInactive
    Stale device threshold in days (default 90).
.PARAMETER OutputDirectory
    Directory for the CSV (default ./out).
.EXAMPLE
    .\Export-DailyTriage.ps1 -DaysInactive 90
.NOTES
    Permissions: Device.Read.All, User.Read.All, Directory.Read.All;
    optional IdentityRiskEvent.Read.All.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 3650)]
    [int]$DaysInactive = 90,

    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

Connect-HelpdeskGraph | Out-Null

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'out'
}
if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$stamp = Get-Date -Format 'yyyy-MM-dd'
$outFile = Join-Path $OutputDirectory "triage-$stamp.csv"
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$DaysInactive)
rows = New-Object System.Collections.Generic.List[object]

Write-HelpdeskLog -Level INFO -Message "Building triage export for $stamp (stale > $DaysInactive days)"

# --- Stale devices ---
try {
    $devices = Get-MgDevice -All -Property 'id,displayName,approximateLastSignInDateTime,accountEnabled,operatingSystem' -ErrorAction Stop
    foreach ($d in $devices) {
        $last = $d.ApproximateLastSignInDateTime
        $isStale = $false
        $lastStr = $null
        if (-not $last) {
            $isStale = $true
            $lastStr = ''
        }
        else {
            $lastUtc = [datetime]::Parse($last.ToString()).ToUniversalTime()
            $lastStr = $lastUtc.ToString('o')
            if ($lastUtc -lt $cutoff) { $isStale = $true }
        }
        if ($isStale) {
            $rows.Add([pscustomobject]@{
                    Category      = 'StaleDevice'
                    Name          = $d.DisplayName
                    ObjectId      = $d.Id
                    Detail        = "OS=$($d.OperatingSystem); LastSignIn=$lastStr; Enabled=$($d.AccountEnabled)"
                    Severity      = 'Medium'
                    CollectedUtc  = (Get-Date).ToUniversalTime().ToString('o')
                }) | Out-Null
        }
    }
}
catch {
    Write-HelpdeskLog -Level WARN -Message "Stale devices section failed: $($_.Exception.Message)"
}

# --- Disabled users that still have licenses ---
try {
    $users = Get-MgUser -All -Property 'id,displayName,userPrincipalName,accountEnabled,assignedLicenses' -ErrorAction Stop
    foreach ($u in $users) {
        $licCount = @($u.AssignedLicenses).Count
        if ((-not $u.AccountEnabled) -and $licCount -gt 0) {
            $rows.Add([pscustomobject]@{
                    Category     = 'DisabledUserWithLicense'
                    Name         = $u.UserPrincipalName
                    ObjectId     = $u.Id
                    Detail       = "DisplayName=$($u.DisplayName); LicenseCount=$licCount"
                    Severity     = 'High'
                    CollectedUtc = (Get-Date).ToUniversalTime().ToString('o')
                }) | Out-Null
        }
    }
}
catch {
    Write-HelpdeskLog -Level WARN -Message "Disabled licensed users section failed: $($_.Exception.Message)"
}

# --- Optional risk signals ---
$riskIncluded = $false
try {
    $riskUri = 'https://graph.microsoft.com/v1.0/identityProtection/riskDetections?$top=50&$orderby=detectedDateTime desc'
    $riskResp = Invoke-MgGraphRequest -Method GET -Uri $riskUri -ErrorAction Stop
    foreach ($r in @($riskResp.value)) {
        $rows.Add([pscustomobject]@{
                Category     = 'RiskDetection'
                Name         = $r.userPrincipalName
                ObjectId     = $r.id
                Detail       = "Risk=$($r.riskDetail); State=$($r.riskState); Activity=$($r.activity); Detected=$($r.detectedDateTime)"
                Severity     = $(if ($r.riskLevel -eq 'high') { 'High' } elseif ($r.riskLevel -eq 'medium') { 'Medium' } else { 'Low' })
                CollectedUtc = (Get-Date).ToUniversalTime().ToString('o')
            }) | Out-Null
    }
    $riskIncluded = $true
}
catch {
    Write-HelpdeskLog -Level WARN -Message "Risk detections skipped (permission missing or API unavailable): $($_.Exception.Message)"
}

$rows.ToArray() | Export-Csv -Path $outFile -NoTypeInformation -Encoding UTF8
Write-HelpdeskLog -Level INFO -Message "Wrote $($rows.Count) rows to $outFile (riskIncluded=$riskIncluded)"
Write-HelpdeskLog -Level AUDIT -Message "Daily triage export" -Properties @{
    Path         = $outFile
    RowCount     = $rows.Count
    RiskIncluded = $riskIncluded
    DaysInactive = $DaysInactive
}

Get-Item -LiteralPath $outFile | Format-List FullName, Length, LastWriteTime
