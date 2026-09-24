#Requires -Version 5.1
<#
.SYNOPSIS
    Revoke Entra sign-in sessions / refresh tokens for a user.
.DESCRIPTION
    Calls Revoke-MgUserSignInSession (invalidate refresh tokens). Typical use:
    compromised account, lost device, or force re-auth after password reset.
    Requires -Confirm or -Force. Supports -WhatIf.
.PARAMETER UserPrincipalName
    Target user UPN.
.PARAMETER Force
    Skip interactive confirmation.
.EXAMPLE
    .\Revoke-UserSessions.ps1 -UserPrincipalName 'jdoe@contoso.com' -WhatIf
.EXAMPLE
    .\Revoke-UserSessions.ps1 -UserPrincipalName 'jdoe@contoso.com' -Confirm
.NOTES
    Permission: User.RevokeSessions.All (application).
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop
Import-Module Microsoft.Graph.Users.Actions -ErrorAction SilentlyContinue

Connect-HelpdeskGraph | Out-Null

$user = Invoke-HelpdeskGraphAction -ActionName 'Get-MgUser' -ScriptBlock {
    Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName' -ErrorAction Stop
}

$target = "{0} <{1}>" -f $user.DisplayName, $user.UserPrincipalName
$action = 'Revoke all sign-in sessions / refresh tokens'

if ($WhatIfPreference) {
    Write-HelpdeskLog -Level INFO -Message "WhatIf: would revoke sessions for $target"
    return
}

if (-not $Force -and -not $PSCmdlet.ShouldProcess($target, $action)) {
    Write-HelpdeskLog -Level INFO -Message "Cancelled."
    return
}

Invoke-HelpdeskGraphAction -ActionName 'Revoke-MgUserSignInSession' -ScriptBlock {
    if (Get-Command Revoke-MgUserSignInSession -ErrorAction SilentlyContinue) {
        Revoke-MgUserSignInSession -UserId $user.Id -ErrorAction Stop
    }
    else {
        Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/users/$($user.Id)/revokeSignInSessions" -ErrorAction Stop
    }
}

Write-HelpdeskLog -Level AUDIT -Message "Revoked sessions for $target" -Properties @{
    UserId            = $user.Id
    UserPrincipalName = $user.UserPrincipalName
}
Write-HelpdeskLog -Level INFO -Message "User must sign in again on all apps. Pair with password reset if compromise is suspected."
