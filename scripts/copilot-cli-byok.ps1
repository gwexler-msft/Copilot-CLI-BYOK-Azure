#requires -Version 7.0
<#
.SYNOPSIS
  Configure the current shell to run `copilot` (GitHub Copilot CLI) against the private APIM,
  or run a one-shot smoke test of the gateway.
.DESCRIPTION
  Exports the four COPILOT_PROVIDER_* environment variables with the per-developer credential,
  and (optionally) runs a curl smoke test against the chat-completions route.

  Two auth modes, matching the gateway's `authMode` Bicep parameter:
    - subscriptionKey (DEFAULT): you present a long-lived per-developer APIM subscription key.
      No token mint, no expiry, no Entra round-trip. This matches the default deployment.
    - jwt: the script mints a short-lived (~1h) Entra JWT for the BYOK API app. Opt in with
      `-AuthMode jwt`. Re-run to refresh the token.

  Notes:
    - The credential rides in COPILOT_PROVIDER_API_KEY (the `api-key` header) because the CLI
      cannot send custom headers (github/copilot-cli#3399). APIM strips it before the backend.
    - jwt mode: with v2 access tokens the JWT 'aud' is the app (client) ID GUID, NOT the api://
      URI. We mint with `--scope "<AppId>/.default"`, which also dodges az's per-resource token
      cache handing back a stale-audience token. Works in AzureCloud and AzureUSGovernment.
.PARAMETER ApimBaseUrl
  Full HTTPS base URL of the APIM gateway INCLUDING the /openai suffix
  (e.g. https://apim-...azure-api.us/openai).
.PARAMETER Model
  Model/deployment name to use (matches what was deployed), e.g. gpt-5.1.
.PARAMETER AuthMode
  'subscriptionKey' (default) or 'jwt'. Selects which credential is sent to the gateway.
.PARAMETER SubscriptionKey
  (subscriptionKey mode) The per-developer APIM subscription key. If omitted, falls back to
  the APIM_SUBSCRIPTION_KEY environment variable. Avoid passing secrets on the command line;
  prefer the env var.
.PARAMETER AppId
  (jwt mode) The app (client) ID GUID of the BYOK gateway app (output of setup-entra). Used as
  the token scope and equals the JWT audience validated by APIM. Required only for -AuthMode jwt.
.PARAMETER ApimPrivateIp
  Optional. APIM Internal-VNet private IP. When set, curl uses --resolve so you do not need a
  hosts entry or private DNS zone. Only used by -Test.
.PARAMETER Test
  Send a chat-completion to the gateway, printing the HTTP status and body.
.PARAMETER PrintOnly
  Export the env vars but do not print the "run copilot now" hint.
.EXAMPLE
  # DEFAULT (subscription key) — configure the shell for the real Copilot CLI:
  $env:APIM_SUBSCRIPTION_KEY = '<your per-developer key>'
  ./copilot-cli-byok.ps1 -ApimBaseUrl 'https://<apim-name>.azure-api.us/openai' `
                         -Model gpt-5.1
  copilot "what does this repo do?"
.EXAMPLE
  # DEFAULT (subscription key) — smoke test from the in-VNet VM (no hosts edit needed):
  ./copilot-cli-byok.ps1 -ApimBaseUrl 'https://<apim-name>.azure-api.us/openai' `
                         -Model gpt-5.1 `
                         -SubscriptionKey '<your per-developer key>' `
                         -ApimPrivateIp 10.60.1.4 `
                         -Test
.EXAMPLE
  # OPT-IN (Entra JWT) — mint a ~1h token instead of using a subscription key:
  ./copilot-cli-byok.ps1 -AuthMode jwt `
                         -AppId <entra-app-client-id> `
                         -ApimBaseUrl 'https://<apim-name>.azure-api.us/openai' `
                         -Model gpt-5.1
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $ApimBaseUrl,
  [Parameter(Mandatory)] [string] $Model,
  [ValidateSet('subscriptionKey', 'jwt')] [string] $AuthMode = 'subscriptionKey',
  [string] $SubscriptionKey,
  [string] $AppId,
  [string] $ApimPrivateIp,
  [switch] $Test,
  [switch] $PrintOnly
)

$ErrorActionPreference = 'Stop'

# Resolve the credential that will ride in the api-key header, per auth mode.
if ($AuthMode -eq 'subscriptionKey') {
  if (-not $SubscriptionKey) { $SubscriptionKey = $env:APIM_SUBSCRIPTION_KEY }
  if (-not $SubscriptionKey) {
    throw 'subscriptionKey mode: provide -SubscriptionKey or set $env:APIM_SUBSCRIPTION_KEY (your per-developer APIM subscription key).'
  }
  $credential = $SubscriptionKey
  $credKind   = 'APIM subscription key'
}
else {
  if (-not $AppId) { throw 'jwt mode: -AppId (the BYOK gateway app/client ID GUID) is required.' }
  $ctx = az account show 2>$null | ConvertFrom-Json
  if (-not $ctx) { throw 'Run `az login` first (use the cloud matching the deployment).' }
  Write-Verbose "Cloud=$($ctx.environmentName) Tenant=$($ctx.tenantId) Account=$($ctx.user.name)"

  # v2 token: scope "<AppId>/.default" => aud == AppId GUID (what APIM validate-jwt expects).
  $credential = az account get-access-token --scope "$AppId/.default" --query accessToken -o tsv 2>$null
  if (-not $credential) {
    throw "Could not get token for $AppId. Did you run setup-entra and is this user able to consent to the 'cli.invoke' scope?"
  }
  $credKind = 'Entra JWT (~1h)'
}

$baseUrl = $ApimBaseUrl.TrimEnd('/')

if ($Test) {
  $uri  = "$baseUrl/v1/chat/completions"
  $body = '{"model":"' + $Model + '","messages":[{"role":"user","content":"say hi in three words"}]}'

  $curlArgs = @('-sk', '-w', "`nhttp=%{http_code}`n", '--max-time', '40')
  if ($ApimPrivateIp) {
    $apimHost = ([Uri]$baseUrl).Host
    $curlArgs += @('--resolve', "${apimHost}:443:$ApimPrivateIp")
  }
  $curlArgs += @('-X', 'POST', $uri,
                 '-H', "api-key: $credential",
                 '-H', 'Content-Type: application/json',
                 '-d', $body)

  Write-Host "POST $uri  (authMode=$AuthMode, model=$Model, credential=$credKind, length=$($credential.Length))"
  & curl.exe @curlArgs
  return
}

$env:COPILOT_PROVIDER_BASE_URL = $baseUrl
$env:COPILOT_PROVIDER_TYPE     = 'azure'
$env:COPILOT_PROVIDER_API_KEY  = $credential
$env:COPILOT_MODEL             = $Model

Write-Host "Configured Copilot CLI for BYOK ($AuthMode):"
Write-Host "  COPILOT_PROVIDER_BASE_URL = $env:COPILOT_PROVIDER_BASE_URL"
Write-Host "  COPILOT_PROVIDER_TYPE     = $env:COPILOT_PROVIDER_TYPE"
Write-Host "  COPILOT_PROVIDER_API_KEY  = <hidden $credKind, length=$($credential.Length)>"
Write-Host "  COPILOT_MODEL             = $env:COPILOT_MODEL"
Write-Host ""
if ($PrintOnly) { return }
if ($AuthMode -eq 'jwt') {
  Write-Host "Token expires in ~1 hour. Re-run to refresh, then run 'copilot'."
}
else {
  Write-Host "Subscription key does not expire. Run 'copilot' now."
}

