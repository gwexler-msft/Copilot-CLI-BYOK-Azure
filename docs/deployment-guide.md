# Deployment Guide

This guide assumes the plan has been reviewed and the Entra tenant + Azure
subscription are picked. **Nothing here is destructive until step 5.**

## 0. Prereqs

- Azure CLI logged in: `az login` (Commercial) or `az login --use-device-code` against Gov.
- Bicep CLI: `az bicep upgrade` (>= 0.30).
- **Contributor** on the subscription (to create the RG, VNet, APIM, AOAI/Foundry, etc.).
- **User Access Administrator** (or Owner) at the subscription/RG scope **if** you deploy with
  `assignAoaiRbac=true` (default). The template creates role assignments
  (`Microsoft.Authorization/roleAssignments/write`) so the APIM managed identity can call AOAI
  **and** Foundry — granting that role is itself a privileged action. In Gov least-privilege
  setups, **activate User Access Administrator as an eligible (PIM) role for the deployment
  window only**; you can deactivate it after the deployment completes. With this active, the
  deployment grants both MI roles itself — there is **no follow-up step**. If you cannot get
  `roleAssignments/write`, set `assignAoaiRbac=false` and have an Owner/UAA run the out-of-band
  grant for **both** accounts (Step 3).
- For the Gov pilot, sign in with an account in your Gov tenant (`*.onmicrosoft.us`).

```pwsh
# Commercial pilot
az cloud set --name AzureCloud
az login
az account set --subscription "<your sub id>"

# Government pilot
az cloud set --name AzureUSGovernment
az login --use-device-code
az account set --subscription "<your gov sub id>"
```

> **Pick your cloud once, here.** Everything downstream follows the active cloud:
> the Entra/Graph scripts read it from `az cloud show`, and the Bicep derives all
> endpoints from the `cloudEnv` parameter. The two clouds differ only in **which
> parameters profile** you start from (next step) — there are no code changes. See
> [Cloud parameterization](architecture.md#cloud-parameterization) for the full
> endpoint matrix and the `services.ai`-zone caveat that is Commercial-only.

## 1. Create the Entra app registration

This is **outside Bicep** because it lives in Microsoft Graph, not ARM.

```pwsh
./scripts/setup-entra.ps1 -DisplayName "copilot-byok-gateway" -ScopeName "cli.invoke"
```

It prints:

```
appIdUri: api://copilot-byok-gateway-<your-tenant-short>
clientId: <guid>
tenantId: <guid>
```

Create your local parameters file from the committed template that matches your cloud,
then fill in these values:

```pwsh
# Government (default pilot):
Copy-Item infra/main.parameters.example.json infra/main.parameters.json

# Commercial: start from the AzureCloud profile instead
#   (cloudEnv=AzureCloud, a commercial region, modelDeploymentSku=GlobalStandard already set):
# Copy-Item infra/main.parameters.commercial.example.json infra/main.parameters.json
```

Edit `infra/main.parameters.json` and replace the `<PLACEHOLDER>` values —
`entraTenantId` (tenantId), `apiAudience` (clientId), `apiAppIdUri` (appIdUri), and
`apimPublisherEmail`. This file is **gitignored** so your tenant-specific values are
never committed; the two `*.example.json` templates are the only parameters files in
source control. For Commercial, also confirm your `location` hosts the model + SKU
(`az cognitiveservices account list-skus`) before deploying.

## 2. Validate the Bicep

```pwsh
az bicep build --file infra/main.bicep
```

If it builds clean, run a what-if at subscription scope:

```pwsh
az deployment sub what-if `
  --location usgovvirginia `
  --template-file infra/main.bicep `
  --parameters @infra/main.parameters.json
```

Read the what-if output. **Stop here and inspect before going further.**

> **Commercial (`AzureCloud`) first run:** use your commercial region for `--location`
> and confirm the plan includes the **`privatelink.services.ai.azure.com`** private DNS
> zone plus its VNet link and the Foundry PE A-record in it. That zone exists only in
> Commercial (Gov derives it as empty and skips it), so a Commercial deployment is the
> only time this path is exercised — verify it here before deploying.

## 3. Deploy infrastructure

```pwsh
az deployment sub create `
  --name "copilot-byok-$(Get-Date -Format yyyyMMdd-HHmm)" `
  --location usgovvirginia `
  --template-file infra/main.bicep `
  --parameters @infra/main.parameters.json
```

This creates the RG, VNet, APIM (takes ~30–45 min), AOAI + PE + DNS, App Insights,
the APIM gateway Private DNS zone (`deployApimPrivateDns`, default true), and
optionally the APIM-MI → AOAI role assignment (`assignAoaiRbac`), the P2S VPN gateway
(`deployVpnGateway`, another ~30 min), and a Windows test VM + Azure Bastion
(`deployTestVm`).

> **Model/SKU (Gov):** `GlobalStandard` does not exist in usgovvirginia. The pilot uses
> **gpt-5.1 (2025-11-13) on DataZoneStandard**, capacity 50.
>
> **Mini tier (auto-routing):** `deployMiniModel=true` also deploys a cheap tier on each
> backend — **gpt-4.1-mini (2025-04-14) on DataZoneStandard**, capacity 50 — used when a
> caller sends the sentinel model `auto`. Confirm the exact mini name/version in your region
> with `az cognitiveservices model list --location <region>` first (`gpt-5.1-mini` is **not**
> available in usgovvirginia). Tune routing via the `autoRoute*` params (threshold 500, band
> 200, classifier off by default). Set `deployMiniModel=false` to skip the tier entirely.
>
> **RBAC:** if your deployer lacks `Microsoft.Authorization/roleAssignments/write`, set
> `assignAoaiRbac=false` and have an Owner/UAA grant the role out-of-band (see below).
>
> **AOAI re-PUT race:** re-running the full `az deployment sub create` can fail with
> `AccountProvisioningStateInvalid` because the template re-PUTs the AOAI account while
> it is still settling. Once AOAI is `Succeeded`, deploy individual modules at RG scope
> (e.g. `infra/modules/apim-aoai-api.bicep`, `apim-private-dns.bicep`, `testvm.bicep`)
> instead of the whole subscription template.
>
> **`api-version` floor:** the gateway injects `api-version` from the
> `aoai-default-api-version` named value (param `defaultAoaiApiVersion`, default
> `2025-04-01-preview`). `gpt-4.1`/`gpt-5.1` need `2025-04-01-preview` or later; an older
> value makes a *live* deployment return `404 Resource not found`. If you patch the named
> value directly on a running APIM, also bump the Bicep default so it survives the next deploy.
>
> **`max_tokens` on gpt-5.x:** the `gpt-5.x` family rejects `max_tokens`
> (`400 ... use 'max_completion_tokens'`); `gpt-4.1-mini` accepts both. When probing the
> sentinel `auto` route (which can land on either tier), send `max_completion_tokens`.

### Out-of-band RBAC (only if `assignAoaiRbac=false`)

With `assignAoaiRbac=false` the template grants the APIM managed identity **no** data-plane
role, so an Owner/UAA must grant `Cognitive Services OpenAI User` on **each deployed account**
— AOAI **and** Foundry. Granting only AOAI makes the gateway return `200` on the `/aoai` path
but `401 PermissionDenied` ("Principal does not have access to API/Operation") on the Foundry
`/openai` path, because the MI cannot reach the Foundry backend.

```pwsh
$apimMi  = az apim show -g rg-copilot-byok-gov-pilot -n <apimName> --query identity.principalId -o tsv
$aoai    = az cognitiveservices account show -g rg-copilot-byok-gov-pilot -n <aoaiName>    --query id -o tsv
$foundry = az cognitiveservices account show -g rg-copilot-byok-gov-pilot -n <foundryName> --query id -o tsv
az role assignment create --assignee-object-id $apimMi --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services OpenAI User" --scope $aoai
az role assignment create --assignee-object-id $apimMi --assignee-principal-type ServicePrincipal `
  --role "Cognitive Services OpenAI User" --scope $foundry
```

### Human playground / direct data-plane access

Both accounts run with **API keys disabled** (`disableLocalAuth=true`). Only APIM's managed
identity has a data-plane role, so the gateway path works but a person opening the Azure AI /
OpenAI **playground** (or calling the account with an SDK) hits an **expected** error:

> *Not authorized: Access to API keys is disabled and the account is missing Chat completion
> permissions. You will need the Cognitive Services OpenAI User role or higher.*

That is the keys-off design, not a fault. Grant humans access one of two ways — both end in the
`Cognitive Services OpenAI User` role on **each** account:

**Option A — IaC-managed (recommended, repeatable).** Add object IDs to the
`playgroundPrincipalIds` param and redeploy. Each principal gets the role on both the AOAI and
Foundry accounts automatically. Works even when `assignAoaiRbac=false`. Prefer a single Entra
**group** so membership changes need no redeploy:

```json
"playgroundPrincipalIds": { "value": [ "<user-or-group-objectId>" ] },
"playgroundPrincipalType": { "value": "Group" }
```

```pwsh
# Look up object IDs
az ad user show --id user@contoso.onmicrosoft.us --query id -o tsv      # a user
az ad group show --group "AI Playground Users" --query id -o tsv         # a group
```

**Option B — manual (one-off, no redeploy).**

```pwsh
$rg = "rg-copilot-byok-gov-pilot"
$aoai    = az cognitiveservices account show -g $rg -n <aoaiName>    --query id -o tsv
$foundry = az cognitiveservices account show -g $rg -n <foundryName> --query id -o tsv
$who = "user@contoso.onmicrosoft.us"   # UPN or objectId
az role assignment create --assignee $who --role "Cognitive Services OpenAI User" --scope $aoai
az role assignment create --assignee $who --role "Cognitive Services OpenAI User" --scope $foundry
```

Use `Cognitive Services OpenAI Contributor` instead if they must also create/manage deployments.

> **VNet caveat:** both accounts have `publicNetworkAccess=Disabled`, so the role is necessary
> but not sufficient — the playground only works from **inside the VNet** (P2S VPN or the test
> VM). A user on the public internet stays blocked even with the role.

## 4. Configure the P2S VPN client

After deployment:

```pwsh
$rg = "rg-copilot-byok-gov-pilot"
$gw = az network vnet-gateway list -g $rg --query "[0].name" -o tsv
az network vnet-gateway vpn-client generate -g $rg -n $gw --processor-architecture Amd64 -o tsv
```

Download the returned URL, install the OpenVPN profile in `AzureVPN/`.

## 5. First developer test

`COPILOT_PROVIDER_BASE_URL` must include the `/openai` suffix. The wrapper defaults to
**`authMode=subscriptionKey`** — the developer presents their per-developer **APIM
subscription key** (set it once in `$env:APIM_SUBSCRIPTION_KEY` to avoid putting the
secret on the command line). Use `-AuthMode jwt -AppId <clientId-guid>` only if the
gateway was deployed with `authMode=jwt`; the `-AppId` is the app **client-ID GUID**
(v2-token audience), not the `api://` URI.

> Get a developer's subscription key from APIM → **Subscriptions** (or the portal
> "Show/Hide keys" action) for the subscription assigned to that developer.

> **Ready-made test keys.** When `deployTestSubscriptions=true` (the default in
> subscription-key mode) the deployment provisions all-APIs APIM subscriptions named
> `dev1` and `dev2` so you can verify the gateway immediately. The deployment output
> `testSubscriptionIds` lists them. Fetch a key with:
>
> ```pwsh
> $rg   = 'rg-copilot-byok-gov-pilot'
> $apim = az deployment sub create ... # or: az apim list -g $rg --query "[0].name" -o tsv
> az apim subscription show -g $rg --service-name $apim --sid dev1 `
>   --query primaryKey -o tsv   # secondaryKey is the backup
> ```
>
> Each `dev1`/`dev2` key is valid for **both** `/openai` (Foundry) and `/aoai` (AOAI),
> and shows up as that name in telemetry (`developer_upn`). Treat them as shared pilot
> test credentials; provision per-person subscriptions for real developers.

### Option A — in-VNet test VM via Bastion (no VPN required)

When `deployTestVm=true`, connect to the VM through the portal (**Connect → Bastion**),
then on the VM:

```pwsh
# Default (subscription key) — no Azure CLI / az login needed for this mode:
$env:APIM_SUBSCRIPTION_KEY = '<your per-developer key>'
./scripts/copilot-cli-byok.ps1 -ApimBaseUrl 'https://apim-...azure-api.us/openai' `
                               -Model gpt-5.1 `
                               -Test

# Opt-in (jwt) — requires Azure CLI + login so a token can be minted:
#   Invoke-WebRequest https://aka.ms/installazurecliwindows -OutFile $env:TEMP\azcli.msi
#   Start-Process msiexec.exe -Wait -ArgumentList "/i `"$env:TEMP\azcli.msi`" /quiet"
#   az cloud set --name AzureUSGovernment; az login --use-device-code
#   ./scripts/copilot-cli-byok.ps1 -AuthMode jwt -AppId <clientId-guid> `
#                                  -ApimBaseUrl 'https://apim-...azure-api.us/openai' -Model gpt-5.1 -Test
```

Expect `http=200` with a completion. (Add `-ApimPrivateIp 10.60.1.4` as a fallback if
DNS hasn't propagated — it makes curl use `--resolve`.)

### Option B — developer laptop over P2S VPN

```pwsh
# On the laptop, after connecting P2S VPN (step 4) — default subscription-key mode:
$env:APIM_SUBSCRIPTION_KEY = '<your per-developer key>'
./scripts/copilot-cli-byok.ps1 -ApimBaseUrl 'https://apim-...azure-api.us/openai' `
                               -Model gpt-5.1
copilot "say hello in exactly five words"
```

Expected: a five-word response. The APIM log + App Insights show the request with the
developer dimension (`developer_oid`/`developer_upn` = the APIM subscription Id/Name in
subscription-key mode, or the Entra `oid`/`upn` in jwt mode).

## 6. Observability check

```pwsh
# Gov caveat: the App Insights query REST API is disabled in this tenant
# (az monitor app-insights query => AADSTS500014). Use the portal Logs blade / workbook.
# Portal -> App Insights -> Logs, then run:
#   customMetrics | where name == 'copilot_byok_request' | take 10
```

You should see rows with `developer_oid`, `developer_upn`, `deployment_name` (and
`backend` on the default Foundry API).

## 7. Tune rate limits & content filtering (optional)

**Rate-limit tiers (subscriptionKey mode).** Developers are grouped via APIM **products**. The
defaults ship two tiers — `byok-standard` and `byok-power` — and `dev1`/`dev2` are assigned to
them. To change a tier's numbers, edit `productTiers` in your parameters file and redeploy:

```jsonc
"productTiers": { "value": [
  { "name": "byok-standard", "displayName": "BYOK Standard", "description": "Standard tier.",
    "callsPerMinute": 60,  "tokensPerMinute": 20000, "monthlyCallQuota": 50000 },
  { "name": "byok-power",    "displayName": "BYOK Power",    "description": "Power tier.",
    "callsPerMinute": 120, "tokensPerMinute": 60000, "monthlyCallQuota": 200000 }
] }
```

Move a developer between tiers by changing the `product` on their entry in `testSubscriptions`
(e.g. `{ "name": "dev1", "product": "byok-power" }`) and redeploying. The `productTiers` numbers
apply **only in subscriptionKey mode** — that is where rate limiting lives (at product scope).
For **jwt mode** there are no products, so the single flat per-developer tier is set instead by
`jwtDefaultCallsPerMinute` / `jwtDefaultTokensPerMinute` / `jwtDefaultMonthlyCallQuota` (these
feed the `jwt-*` named values the jwt policies read). Only the set matching your `authMode` has
any effect; the other is inert. Responses carry `x-byok-calls-remaining`,
`x-byok-tokens-remaining`, and `x-byok-tokens-consumed` headers. See the architecture doc's
"Where rate limiting sits between the two auth modes" for the full comparison.

**Content filtering.** Both the AOAI and Foundry deployments **always** run a content filter —
there is no "off." Out of the box both use Microsoft's built-in default (`Microsoft.DefaultV2`),
so you already have responsible-AI filtering with nothing to configure. Customizing is opt-in via
the single shared `raiPolicyName` parameter. To view or customize:

```pwsh
# Show current filters and per-deployment assignments
./scripts/configure-content-filter.ps1 -ResourceGroup <rg> -AccountName <aoai-or-foundry-account> -Show

# Apply a tightened custom filter and attach it to a deployment
./scripts/configure-content-filter.ps1 -ResourceGroup <rg> -AccountName <account> `
  -Apply -PolicyName byok-strict -ConfigPath ./scripts/content-filter.sample.json `
  -AttachToDeployment gpt-5.1
```

```bash
./scripts/configure-content-filter.sh --resource-group <rg> --account-name <account> --show
```

To persist a custom filter in IaC, set `raiPolicyName` to the policy name in your parameters
file and redeploy — this repoints **both** the AOAI and Foundry deployments to that policy (it's
one shared knob), so the named policy must already exist on each account first (create it with
`-Apply`). **Tightening is always allowed; loosening below Microsoft defaults needs an approved
modified-content-filter application** (the platform rejects an unapproved loosened policy).

## Teardown

```pwsh
az group delete -n rg-copilot-byok-gov-pilot --yes --no-wait
./scripts/setup-entra.ps1 -DisplayName "copilot-byok-gateway" -Remove
```
