#Requires -Version 5.1
<#
.SYNOPSIS
    Reset an Entra user's password (temporary) and force change at next sign-in.
.DESCRIPTION
    App-only path uses Update-MgUser passwordProfile (requires User.ReadWrite.All).
    Requires -Confirm or -Force for the live change. Supports -WhatIf. Writes an
    audit log line (does not write the password into the audit CSV).
.PARAMETER UserPrincipalName
    Target user UPN.
.PARAMETER TemporaryPassword
    Optional temp password. If omitted, a complex password is generated.
.PARAMETER Force
    Skip interactive confirmation (still respects -WhatIf).
.EXAMPLE
    .\Reset-EntraUserPassword.ps1 -UserPrincipalName 'jdoe@contoso.com' -WhatIf
.EXAMPLE
    .\Reset-EntraUserPassword.ps1 -UserPrincipalName 'jdoe@contoso.com' -Confirm
.NOTES
    Modern resetPassword auth-method API is delegated-only. See docs/SETUP.md.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$UserPrincipalName,

    [string]$TemporaryPassword,

    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Users -ErrorAction Stop

Connect-HelpdeskGraph | Out-Null

$user = Invoke-HelpdeskGraphAction -ActionName 'Get-MgUser' -ScriptBlock {
    Get-MgUser -UserId $UserPrincipalName -Property 'id,displayName,userPrincipalName,accountEnabled' -ErrorAction Stop
}

if (-not $TemporaryPassword) {
    $TemporaryPassword = New-HelpdeskTempPassword -Length 16
    Write-HelpdeskLog -Level INFO -Message "Generated temporary password (displayed once below after confirmation)."
}

$target = "{0} <{1}>" -f $user.DisplayName, $user.UserPrincipalName
$action = 'Reset password and force change at next sign-in'

if ($WhatIfPreference) {
    Write-HelpdeskLog -Level INFO -Message "WhatIf: would reset password for $target (forceChangePasswordNextSignIn=true)"
    return
}

if (-not $Force) {
    if (-not $PSCmdlet.ShouldProcess($target, $action)) {
        Write-HelpdeskLog -Level INFO -Message "Cancelled. Re-run with -Confirm or -Force to apply."
        return
    }
}
else {
    Write-HelpdeskLog -Level WARN -Message "Force specified: proceeding without interactive prompt for $target"
}

$passwordProfile = @{
    password                      = $TemporaryPassword
    forceChangePasswordNextSignIn = $true
}

Invoke-HelpdeskGraphAction -ActionName 'Update-MgUser-PasswordProfile' -ScriptBlock {
    Update-MgUser -UserId $user.Id -PasswordProfile $passwordProfile -ErrorAction Stop
}

Write-HelpdeskLog -Level AUDIT -Message "Password reset for $target" -Properties @{
    UserId                    = $user.Id
    UserPrincipalName         = $user.UserPrincipalName
    ForceChangeNextSignIn     = $true
    PasswordDeliveredToOperator = $true
}

Write-Host ""
Write-Host "Temporary password for $target (deliver out-of-band; do not email in cleartext if policy forbids):" -ForegroundColor Yellow
Write-Host $TemporaryPassword -ForegroundColor Yellow
Write-Host ""
Write-HelpdeskLog -Level INFO -Message "Recommend pairing with Revoke-UserSessions.ps1 for compromise tickets."
