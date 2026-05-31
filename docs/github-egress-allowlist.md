# GitHub egress allowlist (corporate proxy / Azure Firewall)

Even with BYOK, the Copilot CLI **still contacts GitHub** for entitlement,
licensing, telemetry, and update checks. None of these endpoints carry your
prompts or completions, but the CLI will not start if it can't reach them.

Allow these FQDNs outbound (HTTPS 443) from developer workstations:

| FQDN | Purpose |
|---|---|
| `api.github.com` | Entitlement + API |
| `github.com` | Login + entitlement redirect |
| `objects.githubusercontent.com` | Static assets |
| `copilot-proxy.githubusercontent.com` | Copilot service proxy (used for non-BYOK; harmless when reachable) |
| `api.githubcopilot.com` | Copilot service API (entitlement) |
| `vscode-auth.github.com` | Auth callback (if devs sign in via VS Code) |
| `default.exp-tas.com` | Treatment Assignment Service (feature flags) |
| `*.actions.githubusercontent.com` | Optional, used if Actions integration is on |
| `update.code.visualstudio.com` | VS Code updates (helpful, not required) |

For Azure Firewall: create an Application Rule Collection with the above as
target FQDNs, source = the AzureVPN client pool (or your corporate proxy egress
range), protocol HTTPS:443.

## Verification

```pwsh
foreach ($h in 'api.github.com','github.com','api.githubcopilot.com') {
  $r = Test-NetConnection -ComputerName $h -Port 443
  '{0,-40} {1}' -f $h, ($(if($r.TcpTestSucceeded){'OK'}else{'BLOCKED'}))
}
```

## Notes

- This list is **outside** Bicep — it's a corporate-network change.
- We do not allow-list `*.openai.azure.com` / `*.openai.azure.us` outbound.
  AOAI traffic stays inside the VNet; the laptop reaches AOAI **only** via
  APIM at its private FQDN.
