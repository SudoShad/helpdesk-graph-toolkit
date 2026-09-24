#Requires -Version 5.1
<#
.SYNOPSIS
    Look up BitLocker recovery keys for an Entra device via Microsoft Graph.
.DESCRIPTION
    Resolves a device by display name or Entra device object id, then lists
    BitLocker recovery keys. By default the key value is redacted in the console.
    Never commit recovery keys to git or tickets without policy approval.
.PARAMETER DeviceName
    Entra device display name (exact match preferred; first match if multiple).
.PARAMETER DeviceId
    Entra directory object id for the device (not the Windows deviceId GUID unless they match in your tenant).
.PARAMETER ShowFullKey
    Print the full recovery key to the console (still not written to CSV by this script).
.EXAMPLE
    .\Get-BitLockerRecoveryKey.ps1 -DeviceName 'LAPTOP-HELP01'
.NOTES
    Permissions: BitlockerKey.Read.All (key material); Device.Read.All (name resolve).
#>
[CmdletBinding(DefaultParameterSetName = 'ByName')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceName,

    [Parameter(Mandatory, ParameterSetName = 'ById')]
    [ValidateNotNullOrEmpty()]
    [string]$DeviceId,

    [switch]$ShowFullKey
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\Common.ps1"

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction SilentlyContinue

Connect-HelpdeskGraph | Out-Null

$deviceObjectId = $null
$deviceDisplay  = $null
$windowsDeviceId = $null

if ($PSCmdlet.ParameterSetName -eq 'ById') {
    $dev = Invoke-HelpdeskGraphAction -ActionName 'Get-MgDevice' -ScriptBlock {
        Get-MgDevice -DeviceId $DeviceId -Property 'id,displayName,deviceId' -ErrorAction Stop
    }
    $deviceObjectId = $dev.Id
    $deviceDisplay  = $dev.DisplayName
    $windowsDeviceId = $dev.DeviceId
}
else {
    $matches = Invoke-HelpdeskGraphAction -ActionName 'Get-MgDevice-Filter' -ScriptBlock {
        Get-MgDevice -Filter "displayName eq '$($DeviceName.Replace("'","''"))'" `
            -Property 'id,displayName,deviceId' -ErrorAction Stop
    }
    $matchList = @($matches)
    if ($matchList.Count -eq 0) {
        throw "No Entra device found with displayName '$DeviceName'."
    }
    if ($matchList.Count -gt 1) {
        Write-HelpdeskLog -Level WARN -Message "Multiple devices named '$DeviceName'; using first. Prefer -DeviceId."
        $matchList | Format-Table Id, DisplayName, DeviceId -AutoSize
    }
    $dev = $matchList[0]
    $deviceObjectId = $dev.Id
    $deviceDisplay  = $dev.DisplayName
    $windowsDeviceId = $dev.DeviceId
}

Write-HelpdeskLog -Level INFO -Message "Device: $deviceDisplay objectId=$deviceObjectId deviceId=$windowsDeviceId"

# BitLocker keys are filtered by the Windows deviceId (deviceId property), not always the directory object id.
$filterId = if ($windowsDeviceId) { $windowsDeviceId } else { $deviceObjectId }

$keys = Invoke-HelpdeskGraphAction -ActionName 'Get-MgBitlockerRecoveryKey' -ScriptBlock {
    # Cmdlet name varies slightly by SDK version; try primary then REST fallback
    if (Get-Command Get-MgInformationProtectionBitlockerRecoveryKey -ErrorAction SilentlyContinue) {
        Get-MgInformationProtectionBitlockerRecoveryKey -Filter "deviceId eq '$filterId'" -All -ErrorAction Stop
    }
    else {
        # Fallback via Invoke-MgGraphRequest
        $uri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$filterId'"
        $resp = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
        $resp.value
    }
}

$keyList = @($keys)
if ($keyList.Count -eq 0) {
    Write-HelpdeskLog -Level WARN -Message "No BitLocker recovery keys found for deviceId=$filterId"
    return
}

foreach ($k in $keyList) {
    $keyId = if ($k.id) { $k.id } elseif ($k.Id) { $k.Id } else { $null }
    $created = if ($k.createdDateTime) { $k.createdDateTime } else { $k.CreatedDateTime }
    $vol = if ($k.volumeType) { $k.volumeType } else { $k.VolumeType }

    # Fetch key material with $select=key
    $fullKey = $null
    try {
        if (Get-Command Get-MgInformationProtectionBitlockerRecoveryKey -ErrorAction SilentlyContinue) {
            $detail = Get-MgInformationProtectionBitlockerRecoveryKey -BitlockerRecoveryKeyId $keyId -Property 'id,createdDateTime,deviceId,volumeType,key' -ErrorAction Stop
            $fullKey = $detail.Key
        }
        else {
            $uri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys/$keyId`?`$select=id,createdDateTime,deviceId,volumeType,key"
            $detail = Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
            $fullKey = $detail.key
        }
    }
    catch {
        Write-HelpdeskLog -Level WARN -Message "Could not read key material for $keyId : $($_.Exception.Message)"
    }

    $displayKey = if (-not $fullKey) {
        '(unavailable)'
    }
    elseif ($ShowFullKey) {
        $fullKey
    }
    else {
        # Redact: show only last segment
        $parts = $fullKey -split '-'
        if ($parts.Count -gt 1) {
            (('****-' * ($parts.Count - 1)) + $parts[-1])
        }
        else {
            '****' + $fullKey.Substring([Math]::Max(0, $fullKey.Length - 4))
        }
    }

    [pscustomobject]@{
        DeviceDisplayName = $deviceDisplay
        DeviceObjectId    = $deviceObjectId
        WindowsDeviceId   = $filterId
        KeyId             = $keyId
        CreatedDateTime   = $created
        VolumeType        = $vol
        RecoveryKey       = $displayKey
        Redacted          = (-not $ShowFullKey)
    }
}

Write-HelpdeskLog -Level AUDIT -Message "BitLocker key lookup for $deviceDisplay" -Properties @{
    DeviceObjectId = $deviceObjectId
    KeyCount       = $keyList.Count
    ShowFullKey    = [bool]$ShowFullKey
}
Write-HelpdeskLog -Level INFO -Message "Reminder: do not commit recovery keys; do not paste into public tickets."
