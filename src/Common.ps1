#Requires -Version 5.1
<#
.SYNOPSIS
    Shared helpers for helpdesk-graph-toolkit scripts.
.DESCRIPTION
    Connect-HelpdeskGraph, logging/transcript helpers, optional tenant allowlist,
    and consistent error handling. Dot-source from scripts:

        . "$PSScriptRoot\Common.ps1"
#>

$script:HelpdeskToolkitVersion = '1.0.0'
$script:HelpdeskAuditPath = $null
$script:HelpdeskTranscriptPath = $null

function Write-HelpdeskLog {
    <#
    .SYNOPSIS
        Write a structured log line to the host and optional audit CSV.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'AUDIT')]
        [string]$Level,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [hashtable]$Properties
    )

    $timestamp = (Get-Date).ToString('o')
    $line = "[{0}] [{1}] {2}" -f $timestamp, $Level, $Message
    switch ($Level) {
        'ERROR' { Write-Error $Message; break }
        'WARN'  { Write-Warning $Message; break }
        default { Write-Host $line }
    }

    if ($script:HelpdeskAuditPath) {
        $row = [pscustomobject]@{
            Timestamp = $timestamp
            Level     = $Level
            Message   = $Message
            Detail    = if ($Properties) { ($Properties.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) -join '; ' } else { '' }
        }
        $dir = Split-Path -Parent $script:HelpdeskAuditPath
        if ($dir -and -not (Test-Path -LiteralPath $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if (-not (Test-Path -LiteralPath $script:HelpdeskAuditPath)) {
            $row | Export-Csv -Path $script:HelpdeskAuditPath -NoTypeInformation -Encoding UTF8
        }
        else {
            $row | Export-Csv -Path $script:HelpdeskAuditPath -NoTypeInformation -Encoding UTF8 -Append
        }
    }
}

function Start-HelpdeskTranscript {
    <#
    .SYNOPSIS
        Start a PowerShell transcript under ./out/transcripts (gitignored via out/).
    #>
    [CmdletBinding()]
    param(
        [string]$OutputDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'out\transcripts')
    )
    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }
    $script:HelpdeskTranscriptPath = Join-Path $OutputDirectory ("transcript-{0:yyyyMMdd-HHmmss}.txt" -f (Get-Date))
    Start-Transcript -Path $script:HelpdeskTranscriptPath -Append | Out-Null
    Write-HelpdeskLog -Level INFO -Message "Transcript started: $($script:HelpdeskTranscriptPath)"
}

function Stop-HelpdeskTranscript {
    [CmdletBinding()]
    param()
    try {
        Stop-Transcript | Out-Null
        Write-HelpdeskLog -Level INFO -Message "Transcript stopped: $($script:HelpdeskTranscriptPath)"
    }
    catch {
        # No active transcript
    }
}

function Set-HelpdeskAuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )
    $script:HelpdeskAuditPath = $Path
    Write-HelpdeskLog -Level INFO -Message "Audit CSV set: $Path"
}

function Assert-NotProduction {
    <#
    .SYNOPSIS
        Fail closed if connected tenant is not in HG_ALLOWED_TENANTS allowlist.
    .DESCRIPTION
        Optional safety rail. If HG_ALLOWED_TENANTS is unset/empty, this is a no-op
        (with a warning). Set a comma-separated list of tenant GUIDs to enforce.
    #>
    [CmdletBinding()]
    param(
        [string]$AllowedTenantsEnv = 'HG_ALLOWED_TENANTS'
    )

    $raw = [Environment]::GetEnvironmentVariable($AllowedTenantsEnv)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Write-HelpdeskLog -Level WARN -Message "Assert-NotProduction: $AllowedTenantsEnv not set; skipping allowlist check."
        return
    }

    $ctx = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $ctx) {
        throw "Assert-NotProduction: not connected. Call Connect-HelpdeskGraph first."
    }

    $allowed = $raw.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ }
    $current = ($ctx.TenantId | ForEach-Object { $_.ToString().ToLowerInvariant() })
    if ($current -notin $allowed) {
        throw "Assert-NotProduction: tenant '$current' is not in allowlist ($AllowedTenantsEnv). Refusing to continue."
    }
    Write-HelpdeskLog -Level INFO -Message "Tenant allowlist OK: $current"
}

function Connect-HelpdeskGraph {
    <#
    .SYNOPSIS
        Connect to Microsoft Graph using HG_* environment variables.
    .DESCRIPTION
        Prefers certificate thumbprint (HG_CERT_THUMBPRINT). Falls back to
        HG_CLIENT_SECRET for short-lived lab use. Requires Microsoft.Graph.Authentication.
    #>
    [CmdletBinding()]
    param(
        [string[]]$AdditionalScopes
    )

    $modules = @(
        'Microsoft.Graph.Authentication'
    )
    foreach ($m in $modules) {
        if (-not (Get-Module -ListAvailable -Name $m)) {
            throw "Module '$m' not found. Install per docs/SETUP.md (Install-Module Microsoft.Graph.Authentication)."
        }
        Import-Module $m -ErrorAction Stop
    }

    # Import commonly used Graph submodules when present (scripts also Import-Module as needed)
    $optional = @(
        'Microsoft.Graph.Users',
        'Microsoft.Graph.Users.Actions',
        'Microsoft.Graph.Identity.DirectoryManagement',
        'Microsoft.Graph.Identity.SignIns',
        'Microsoft.Graph.Groups'
    )
    foreach ($m in $optional) {
        if (Get-Module -ListAvailable -Name $m) {
            Import-Module $m -ErrorAction SilentlyContinue
        }
    }

    $tenantId = $env:HG_TENANT_ID
    $clientId = $env:HG_CLIENT_ID
    $thumb    = $env:HG_CERT_THUMBPRINT
    $secret   = $env:HG_CLIENT_SECRET

    if ([string]::IsNullOrWhiteSpace($tenantId) -or [string]::IsNullOrWhiteSpace($clientId)) {
        throw "Set HG_TENANT_ID and HG_CLIENT_ID environment variables before connecting. See docs/SETUP.md."
    }

    $existing = Get-MgContext -ErrorAction SilentlyContinue
    if ($existing -and $existing.TenantId -eq $tenantId -and $existing.ClientId -eq $clientId) {
        Write-HelpdeskLog -Level INFO -Message "Already connected to tenant $($existing.TenantId) as app $($existing.ClientId)"
        Assert-NotProduction
        return $existing
    }

    Write-HelpdeskLog -Level INFO -Message "Connecting to Microsoft Graph (app-only)..."

    if (-not [string]::IsNullOrWhiteSpace($thumb)) {
        Connect-MgGraph -TenantId $tenantId -ClientId $clientId -CertificateThumbprint $thumb -NoWelcome -ErrorAction Stop
    }
    elseif (-not [string]::IsNullOrWhiteSpace($secret)) {
        Write-HelpdeskLog -Level WARN -Message "Using client secret (lab only). Prefer HG_CERT_THUMBPRINT."
        $secure = ConvertTo-SecureString -String $secret -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($clientId, $secure)
        # Client secret auth via Connect-MgGraph -ClientSecretCredential (SDK 2.x)
        Connect-MgGraph -TenantId $tenantId -ClientSecretCredential $cred -NoWelcome -ErrorAction Stop
    }
    else {
        throw "Set HG_CERT_THUMBPRINT (preferred) or HG_CLIENT_SECRET. See docs/SETUP.md."
    }

    $ctx = Get-MgContext
    Write-HelpdeskLog -Level INFO -Message "Connected. Tenant=$($ctx.TenantId) App=$($ctx.ClientId) Auth=$($ctx.AuthType)"
    Assert-NotProduction
    return $ctx
}

function Invoke-HelpdeskGraphAction {
    <#
    .SYNOPSIS
        Wrap a scriptblock with consistent try/catch logging.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [string]$ActionName = 'GraphAction'
    )
    try {
        & $ScriptBlock
    }
    catch {
        Write-HelpdeskLog -Level ERROR -Message "$ActionName failed: $($_.Exception.Message)" -Properties @{
            Exception = $_.Exception.GetType().FullName
        }
        throw
    }
}

function New-HelpdeskTempPassword {
    <#
    .SYNOPSIS
        Generate a complex temporary password (not stored in repo/logs by default).
    #>
    [CmdletBinding()]
    param(
        [ValidateRange(12, 64)]
        [int]$Length = 16
    )
    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbols = '!@#$%*-_+='
    $all = $upper + $lower + $digits + $symbols
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes = New-Object byte[] $Length
    $rng.GetBytes($bytes)
    $chars = New-Object char[] $Length
    for ($i = 0; $i -lt $Length; $i++) {
        $chars[$i] = $all[$bytes[$i] % $all.Length]
    }
    # Ensure complexity classes
    $chars[0] = $upper[$bytes[0] % $upper.Length]
    $chars[1] = $lower[$bytes[1] % $lower.Length]
    $chars[2] = $digits[$bytes[2] % $digits.Length]
    $chars[3] = $symbols[$bytes[3] % $symbols.Length]
    -join $chars
}

Export-ModuleMember -Function * -ErrorAction SilentlyContinue
