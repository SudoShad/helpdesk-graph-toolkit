# Operator runbook

Prerequisites: Graph modules installed, app registration consented, `HG_*` env vars set. See [SETUP.md](SETUP.md).

All commands assume the repo root as the working directory.

```powershell
cd path\to\helpdesk-graph-toolkit
. .\src\Common.ps1
Connect-HelpdeskGraph
```

---

## Get-StaleEntraDevices.ps1

| | |
|--|--|
| **When** | Device hygiene: find Entra devices not seen in *N* days |
| **Inputs** | `-DaysInactive` (default 90), `-ExportPath`, `-DisableStale` (optional), `-WhatIf` (default when disabling) |
| **Output** | Console table + CSV with DeviceId, DisplayName, ApproximateLastSignInDateTime, AccountEnabled |
| **Rollback** | If you disabled devices, re-enable in Entra portal or `Update-MgDevice -DeviceId <id> -AccountEnabled` |
| **Notes** | Disable is off by default. Pass `-DisableStale -Confirm` (or `-Force`) and omit `-WhatIf` only after review. |

```powershell
.\src\Get-StaleEntraDevices.ps1 -DaysInactive 90 -ExportPath .\out\stale-devices.csv
.\src\Get-StaleEntraDevices.ps1 -DaysInactive 180 -DisableStale -WhatIf
```

---

## Get-BitLockerRecoveryKey.ps1

| | |
|--|--|
| **When** | User locked out of BitLocker; deskside needs recovery key |
| **Inputs** | `-DeviceName` **or** `-DeviceId` (Entra device object id), `-ShowFullKey` (optional) |
| **Output** | Key id, created time, volume type; key value redacted by default (`****-****-…` last segment shown) |
| **Rollback** | N/A (read-only) |
| **Notes** | Requires `BitlockerKey.Read.All`. Never paste keys into tickets/email without policy. Never commit keys. |

```powershell
.\src\Get-BitLockerRecoveryKey.ps1 -DeviceName 'LAPTOP-HELP01'
.\src\Get-BitLockerRecoveryKey.ps1 -DeviceId '<entra-device-guid>' -ShowFullKey
```

---

## Reset-EntraUserPassword.ps1

| | |
|--|--|
| **When** | Password reset ticket; force change at next sign-in |
| **Inputs** | `-UserPrincipalName`, `-TemporaryPassword` (optional; auto-generated if omitted), `-Confirm` or `-Force`, `-WhatIf` |
| **Output** | Audit line to transcript/CSV; temporary password printed once (secure channel only) |
| **Rollback** | User signs in with temp password and sets a new one; or admin resets again |
| **Notes** | App-only path uses `passwordProfile`. Destructive — requires `-Confirm`/`-Force`. Prefer out-of-band delivery of temp password. |

```powershell
.\src\Reset-EntraUserPassword.ps1 -UserPrincipalName 'jdoe@contoso.com' -WhatIf
.\src\Reset-EntraUserPassword.ps1 -UserPrincipalName 'jdoe@contoso.com' -Confirm
```

---

## Get-HelpdeskUserSummary.ps1

| | |
|--|--|
| **When** | First look at an account for access / license / device tickets |
| **Inputs** | `-UserPrincipalName`, `-TopGroups` (default 10) |
| **Output** | Enabled state, assigned licenses (sku ids/names if resolvable), top groups, last sign-in (if property available), registered devices |
| **Rollback** | N/A (read-only) |
| **Notes** | Last sign-in needs `signInActivity` (often `AuditLog.Read.All` or enriched User.Read.All depending on license); script notes when unavailable. |

```powershell
.\src\Get-HelpdeskUserSummary.ps1 -UserPrincipalName 'jdoe@contoso.com'
```

---

## Export-DailyTriage.ps1

| | |
|--|--|
| **When** | Start-of-day hygiene: stale devices, disabled users with licenses, optional risk signals |
| **Inputs** | `-DaysInactive` (default 90), `-OutputDirectory` (default `.\out`) |
| **Output** | Dated CSV e.g. `out/triage-2026-09-24.csv` |
| **Rollback** | N/A (read/export only) |
| **Notes** | Risk section skipped with a warning if `IdentityRiskEvent.Read.All` is missing. Sample shape: [`examples/sample-triage.csv`](../examples/sample-triage.csv). |

```powershell
.\src\Export-DailyTriage.ps1 -DaysInactive 90
```

---

## Revoke-UserSessions.ps1

| | |
|--|--|
| **When** | Suspected compromise, lost device, or forced re-auth after password reset |
| **Inputs** | `-UserPrincipalName`, `-Confirm` or `-Force`, `-WhatIf` |
| **Output** | Success/failure; audit log line |
| **Rollback** | User re-authenticates; no “undo” of revoke (by design) |
| **Notes** | Uses `Revoke-MgUserSignInSession`. Pair with password reset for compromise tickets. |

```powershell
.\src\Revoke-UserSessions.ps1 -UserPrincipalName 'jdoe@contoso.com' -WhatIf
.\src\Revoke-UserSessions.ps1 -UserPrincipalName 'jdoe@contoso.com' -Confirm
```

---

## Disconnect

```powershell
Disconnect-MgGraph
Stop-HelpdeskTranscript   # if you started one via Common.ps1
```
