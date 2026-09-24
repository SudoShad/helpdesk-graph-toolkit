# Setup — Entra app registration & Graph modules

This guide wires the toolkit to a **real** Microsoft Entra ID tenant. Scripts expect app-only (client credentials) auth for most reads/writes, with one exception noted for password reset.

> Replace every GUID and name with your own. Do not commit tenant IDs, secrets, certificates, or `.env` files.

---

## 1. Install Graph PowerShell modules

```powershell
# PowerShell 7 recommended; Windows PowerShell 5.1 also works
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
Install-Module Microsoft.Graph.Users.Actions -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.DirectoryManagement -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser
Install-Module Microsoft.Graph.Groups -Scope CurrentUser
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser   # optional / Intune-adjacent
```

Or the meta-module (larger download):

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

Verify:

```powershell
Get-Module Microsoft.Graph* -ListAvailable | Select-Object Name, Version
```

---

## 2. Register an Entra application

1. Open [Microsoft Entra admin center](https://entra.microsoft.com) → **App registrations** → **New registration**.
2. Name: e.g. `helpdesk-graph-toolkit-lab` (single tenant).
3. Supported account types: **Accounts in this organizational directory only**.
4. No redirect URI required for pure app-only client-credentials.
5. Note **Application (client) ID** and **Directory (tenant) ID**.

### Authentication credential (prefer certificate)

**Preferred — certificate**

1. Create a self-signed cert (lab) or use your org PKI.
2. Upload the public `.cer` under **Certificates & secrets** → **Certificates**.
3. Keep the private key (`.pfx`) on the operator workstation only — never in git.
4. Note the certificate **thumbprint**.

**Acceptable for short-lived lab — client secret**

1. **Certificates & secrets** → **New client secret**.
2. Copy the value once; store in env / SecretStore.
3. Treat secrets as short-lived; prefer rotating to a certificate.

---

## 3. Application permissions (admin consent required)

Add **Microsoft Graph → Application permissions**, then click **Grant admin consent**.

| Permission | Type | Used by | Purpose |
|------------|------|---------|---------|
| `Device.Read.All` | Application | Stale devices, user summary, BitLocker (device resolve) | List / read Entra devices |
| `Device.ReadWrite.All` | Application | Optional disable in stale-devices script | Disable stale device objects |
| `BitlockerKey.Read.All` | Application | BitLocker recovery key | Read recovery key material (`$select=key`) |
| `BitlockerKey.ReadBasic.All` | Application | BitLocker metadata-only | List keys without key material (optional lighter scope) |
| `User.Read.All` | Application | User summary, triage | Read users, licenses, sign-in activity |
| `User.ReadWrite.All` | Application | Password reset via `passwordProfile` (app-only path) | Update user profile including temporary password |
| `User.RevokeSessions.All` | Application | Revoke sessions | Invalidate refresh tokens / sessions |
| `Directory.Read.All` | Application | Groups, directory lookups | Read directory data (groups membership) |
| `Group.Read.All` | Application | User summary | Read group membership (if not covered by Directory.Read.All alone in your module version) |
| `IdentityRiskEvent.Read.All` | Application | Daily triage (optional) | Read Identity Protection risk events; script skips gracefully if missing |

### Password reset — important nuance

Microsoft’s modern `resetPassword` authentication-method API supports **delegated** `UserAuthenticationMethod.ReadWrite.All` only (not Application). For **app-only** helpdesk automation this toolkit uses `Update-MgUser` with `passwordProfile` and `User.ReadWrite.All`, then forces change at next sign-in. For interactive helpdesk consoles, prefer delegated auth + Helpdesk Administrator / Password Administrator role.

Delegated alternative (interactive):

```powershell
Connect-MgGraph -Scopes 'UserAuthenticationMethod.ReadWrite.All','User.Read.All'
```

---

## 4. Store secrets outside the repo

### Environment variables (simple)

```powershell
# Session example — do not put these in profile files that sync to git
$env:HG_TENANT_ID  = '<your-tenant-guid>'
$env:HG_CLIENT_ID  = '<your-app-client-guid>'
$env:HG_CERT_THUMBPRINT = '<cert-thumbprint>'   # preferred
# OR for lab secrets only:
# $env:HG_CLIENT_SECRET = '<secret-value>'

# Optional allowlist (comma-separated tenant GUIDs)
$env:HG_ALLOWED_TENANTS = $env:HG_TENANT_ID
```

### SecretStore pattern (recommended on shared workstations)

```powershell
Install-Module Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore -Scope CurrentUser
Register-SecretVault -Name LocalStore -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Set-Secret -Name HG_CLIENT_SECRET -Secret (Read-Host -AsSecureString 'Client secret')
# Scripts can call Get-Secret when env var is absent — extend Common.ps1 if desired
```

Never commit `.env`, `*.pfx`, or `tenant.allowlist.json` with real IDs (see `.gitignore`).

---

## 5. Connect pattern

`src/Common.ps1` exposes `Connect-HelpdeskGraph`:

```powershell
. .\src\Common.ps1
Connect-HelpdeskGraph   # uses HG_* env vars; certificate preferred
Get-MgContext
```

Manual equivalent:

```powershell
Connect-MgGraph -TenantId $env:HG_TENANT_ID -ClientId $env:HG_CLIENT_ID `
  -CertificateThumbprint $env:HG_CERT_THUMBPRINT
```

---

## 6. Smoke test (no mutations)

```powershell
. .\src\Common.ps1
Connect-HelpdeskGraph
Get-MgUser -Top 1 | Format-List DisplayName, UserPrincipalName
Disconnect-MgGraph
```

Then run [`tests/Smoke-Syntax.ps1`](../tests/Smoke-Syntax.ps1) to validate script parsing without calling Graph.

---

## Least privilege tips

- Start with **read** permissions; add `Device.ReadWrite.All` / `User.ReadWrite.All` only when you need disable or password reset.
- Use a dedicated lab or non-prod tenant while learning.
- Set `HG_ALLOWED_TENANTS` so a mis-pointed credential fails closed.
- Rotate client secrets; prefer certificates with documented expiry.
