#Requires -Version 5.1
<#
.SYNOPSIS
    Parse/validate toolkit scripts without calling Microsoft Graph.
.DESCRIPTION
    Uses System.Management.Automation.Language.Parser (and optionally pwsh AST)
    to ensure scripts parse. Exit code 0 = all OK; non-zero = failures listed.
.EXAMPLE
    .\tests\Smoke-Syntax.ps1
#>
[CmdletBinding()]
param(
    [string]$SrcDirectory
)

$ErrorActionPreference = 'Stop'

if (-not $SrcDirectory) {
    $SrcDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
}

$files = Get-ChildItem -Path $SrcDirectory -Filter '*.ps1' -File | Sort-Object Name
if ($files.Count -eq 0) {
    Write-Error "No .ps1 files under $SrcDirectory"
    exit 1
}

$failures = @()
foreach ($f in $files) {
    $tokens = $null
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        foreach ($e in $errors) {
            $failures += "[$($f.Name)] $($e.Message) (line $($e.Extent.StartLineNumber))"
        }
        Write-Host "FAIL  $($f.Name)" -ForegroundColor Red
    }
    else {
        Write-Host "OK    $($f.Name) ($($tokens.Count) tokens)" -ForegroundColor Green
    }
}

# Also parse this test file and Common is included via src

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Smoke-Syntax FAILED ($($failures.Count) error(s)):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Smoke-Syntax PASSED ($($files.Count) scripts)" -ForegroundColor Green
exit 0
