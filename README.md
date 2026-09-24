# Helpdesk Graph Toolkit

**Author:** Shadman Bari · [shadman.io](https://shadman.io) · [LinkedIn](https://linkedin.com/in/shadman-bari) · shadman@shadman.io  
**Focus:** Windows / Microsoft 365 helpdesk automation (Entra ID + Graph)  
**Companion:** [endpoint-hardening-baseline](https://github.com/SudoShad/endpoint-hardening-baseline) (Intune hardening policy-as-code) · [linux-ops-toolkit](https://github.com/SudoShad/linux-ops-toolkit) (Linux bash ops) · [linux-homelab](https://github.com/SudoShad/linux-homelab) · [ad-intune-mini-tenant](https://github.com/SudoShad/ad-intune-mini-tenant) *(Intune lab — PARKED)*

PowerShell scripts for common Desktop Support / IT Support tickets against Microsoft Entra ID via Microsoft Graph. Built for Queens–NYC deskside and Jr Sysadmin interviews — honest automation you can wire to a real tenant with an app registration.

> No secrets in this repo. No fake screenshots or invented metrics. Scripts ship with `-WhatIf` / dry-run defaults on mutating actions.

---

## Problem

Helpdesk queues repeat the same Entra tasks: find stale devices, pull a BitLocker key, reset a password, summarize a user for a ticket, revoke sessions after a compromised-account call, and produce a daily triage CSV. Doing these only in the portal is slow and hard to audit. This toolkit wraps those workflows in parameter-driven scripts with shared logging and least-privilege Graph scopes.

---

## What it does

| Script | Ticket pattern |
|--------|----------------|
| [`Get-StaleEntraDevices.ps1`](src/Get-StaleEntraDevices.ps1) | List Entra devices with last sign-in older than *N* days; export CSV; optional disable (`-WhatIf` default) |
| [`Get-BitLockerRecoveryKey.ps1`](src/Get-BitLockerRecoveryKey.ps1) | Look up BitLocker recovery key by device name or Entra device id; redacted console output |
| [`Reset-EntraUserPassword.ps1`](src/Reset-EntraUserPassword.ps1) | Temporary password + force change at next sign-in; requires `-Confirm` or `-Force`; supports `-WhatIf` |
| [`Get-HelpdeskUserSummary.ps1`](src/Get-HelpdeskUserSummary.ps1) | One-pane summary: enabled, licenses, groups, last sign-in, registered devices |
| [`Export-DailyTriage.ps1`](src/Export-DailyTriage.ps1) | Combine stale devices + disabled users still licensed (+ risky signals if permitted) → dated CSV under `./out/` |
| [`Revoke-UserSessions.ps1`](src/Revoke-UserSessions.ps1) | Revoke refresh tokens / sign-in sessions for compromised-user style tickets |

Shared helpers live in [`src/Common.ps1`](src/Common.ps1) (connect stub, transcript/CSV logging, optional tenant allowlist).

---

## Setup (high level)

1. Register an Entra app (single-tenant) and grant **Application** permissions with admin consent — see [`docs/SETUP.md`](docs/SETUP.md) for the exact scope table.
2. Prefer a **certificate** over a client secret for app-only auth; store credentials outside the repo (env vars or SecretStore).
3. Install Microsoft Graph PowerShell modules (`Microsoft.Graph.Authentication`, plus device/user/identity modules as listed in SETUP).
4. Set `HG_TENANT_ID`, `HG_CLIENT_ID`, and cert thumbprint / secret via environment — never commit them.
5. Optionally set `HG_ALLOWED_TENANTS` (comma-separated GUIDs) so scripts refuse unexpected tenants.

Operator steps for each script: [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

---

## Safety

- Mutating scripts honor **`-WhatIf`** (and Prefer: disable/password/revoke require explicit `-Confirm` or `-Force`).
- **No secrets, tenant IDs, recovery keys, or real CSVs** belong in git. `out/`, `*.pfx`, `.env`, and local CSVs are gitignored.
- BitLocker output redacts the key unless you pass `-ShowFullKey` (still never write keys to committed files).
- `Assert-NotProduction` in Common.ps1 can block runs when the connected tenant is not on an allowlist.

---

## Resume bullet (paste-ready)

> Built a public **PowerShell + Microsoft Graph helpdesk toolkit** (`helpdesk-graph-toolkit`) for Entra IT support tasks — stale device triage, BitLocker key lookup, password reset with audit logging, user summary, session revoke, and daily CSV export — using least-privilege app permissions, `-WhatIf` defaults, and secrets kept outside the repo.

---

## Skills demonstrated

- Microsoft Graph / Entra ID helpdesk automation  
- Least-privilege application permissions and admin consent  
- PowerShell 5.1 / 7 scripting (`#Requires`, comment-based help, parameter validation)  
- Safe change control (`-WhatIf`, `-Confirm`, audit CSV / transcript)  
- Desktop Support ticket patterns (BitLocker, password, compromise revoke, device hygiene)  

---

## Repo map

| Path | Purpose |
|------|---------|
| [`src/`](src/) | Scripts + `Common.ps1` |
| [`docs/SETUP.md`](docs/SETUP.md) | App registration, scopes, secret storage |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | When/how to run each script |
| [`examples/sample-triage.csv`](examples/sample-triage.csv) | **EXAMPLE** output shape only |
| [`tests/Smoke-Syntax.ps1`](tests/Smoke-Syntax.ps1) | AST / parser smoke test (no live Graph) |

---

## Related labs

| Repo | Role |
|------|------|
| [endpoint-hardening-baseline](https://github.com/SudoShad/endpoint-hardening-baseline) | CIS-inspired Intune / policy-as-code Windows hardening |
| [linux-ops-toolkit](https://github.com/SudoShad/linux-ops-toolkit) | POSIX `sh` backup / SSH guard / health check |
| [linux-homelab](https://github.com/SudoShad/linux-homelab) | Proxmox + AD/GPO + WireGuard + osTicket + Wazuh |
| [ad-intune-mini-tenant](https://github.com/SudoShad/ad-intune-mini-tenant) | Entra + Intune enroll lab — **PARKED** |

---

## Requirements

- Windows PowerShell 5.1+ or PowerShell 7+  
- Microsoft Graph PowerShell SDK modules (see SETUP)  
- Entra ID tenant + app registration with admin-consented Application permissions (or delegated interactive for password reset — documented in SETUP)

---

## License

MIT © 2026 Shadman Bari — see [LICENSE](LICENSE).
