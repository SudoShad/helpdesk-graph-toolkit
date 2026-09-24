#Requires -Version 5.1
<#
.SYNOPSIS
    One-pane Entra user summary for helpdesk tickets.
.DESCRIPTION
    Shows account enabled, assigned licenses, top N groups, last sign-in when
    available, and registered devices.
.PARAMETER UserPrincipalName
    Target user UPN.
.PARAMETER TopGroups
    Max group display names to list (default 10).
.EXAMPLE
    .\Get-HelpdeskUserSummary.ps1 -UserPrincipalName 'jdoe@contoso.com'
.NOTES
    Permissions: User.Read.All, Directory.Read.All / Group.Read.All, Device.Read.All.
    signInActivity may require additional audit permissions / Entra ID P1+.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [ValidateRange(1, 100)]
    [int]$TopGroups = 10
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Groups -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop

Connect-HelpdeskGraph | Out-Null

$user = Invoke-HelpdeskGraphAction -ActionName 'Get-MgUser' -ScriptBlock {
    Get-MgUser -UserId $UserPrincipalName `
        -Property 'id,displayName,userPrincipalName,accountEnabled,assignedLicenses,createdDateTime,jobTitle,department,officeLocation,mobilePhone,mail' `
        -ErrorAction Stop
}

# Best-effort sign-in activity
$lastSignIn = $null
$signInNote = 'unavailable'
try {
    $withSignIn = Get-MgUser -UserId $user.Id -Property 'signInActivity' -ErrorAction Stop
    if ($withSignIn.SignInActivity) {
        $lastSignIn = $withSignIn.SignInActivity.LastSignInDateTime
        $signInNote = 'signInActivity'
    }
}
catch {
    $signInNote = "signInActivity not available ($($_.Exception.Message))"
}

$skuIds = @($user.AssignedLicenses | ForEach-Object { $_.SkuId })

$groups = @()
try {
    $memberOf = Get-MgUserMemberOf -UserId $user.Id -All -ErrorAction Stop
    $groups = @(
        $memberOf |
            Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' -or $_.AdditionalProperties.'@odata.type' -eq '#microsoft.graph.group' } |
            Select-Object -First $TopGroups |
            ForEach-Object {
                if ($_.DisplayName) { $_.DisplayName }
                elseif ($_.AdditionalProperties.displayName) { $_.AdditionalProperties.displayName }
                else { $_.Id }
            }
    )
}
catch {
    Write-HelpdeskLog -Level WARN -Message "Could not list groups: $($_.Exception.Message)"
}

$devices = @()
try {
    $reg = Get-MgUserRegisteredDevice -UserId $user.Id -All -ErrorAction Stop
    $devices = @($reg | ForEach-Object {
            $name = if ($_.DisplayName) { $_.DisplayName } elseif ($_.AdditionalProperties.displayName) { $_.AdditionalProperties.displayName } else { $_.Id }
            $enabled = if ($null -ne $_.AccountEnabled) { $_.AccountEnabled } elseif ($null -ne $_.AdditionalProperties.accountEnabled) { $_.AdditionalProperties.accountEnabled } else { $null }
            [pscustomobject]@{ DisplayName = $name; AccountEnabled = $enabled; Id = $_.Id }
        })
}
catch {
    Write-HelpdeskLog -Level WARN -Message "Could not list registered devices: $($_.Exception.Message)"
}

$summary = [pscustomobject]@{
    DisplayName           = $user.DisplayName
    UserPrincipalName     = $user.UserPrincipalName
    UserId                = $user.Id
    AccountEnabled        = $user.AccountEnabled
    JobTitle              = $user.JobTitle
    Department            = $user.Department
    Mail                  = $user.Mail
    CreatedDateTime       = $user.CreatedDateTime
    LicenseSkuCount       = $skuIds.Count
    LicenseSkuIds         = ($skuIds -join ', ')
    GroupsTopN            = ($groups -join '; ')
    GroupCountReturned    = $groups.Count
    LastSignInDateTime    = $lastSignIn
    LastSignInSource      = $signInNote
    RegisteredDeviceCount = $devices.Count
    RegisteredDevices     = (($devices | ForEach-Object { $_.DisplayName }) -join '; ')
}

$summary | Format-List
if ($devices.Count -gt 0) {
    Write-Host "Registered devices:" -ForegroundColor Cyan
    $devices | Format-Table -AutoSize
}

Write-HelpdeskLog -Level AUDIT -Message "User summary for $($user.UserPrincipalName)" -Properties @{
    UserId         = $user.Id
    AccountEnabled = $user.AccountEnabled
    LicenseCount   = $skuIds.Count
}
