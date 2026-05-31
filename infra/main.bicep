targetScope = 'subscription'

@description('Short prefix used in all resource names. Lowercase, alpha-only.')
param namePrefix string = 'copilot-byok'

@description('Environment short name, e.g. gov-pilot, dev, prod. Used in names.')
param envName string = 'gov-pilot'

@description('Azure region for all resources.')
param location string = 'usgovvirginia'

@description('Cloud environment. Drives DNS suffixes and Entra endpoints.')
@allowed([
  'AzureCloud'
  'AzureUSGovernment'
])
param cloudEnv string = 'AzureUSGovernment'

@description('CIDR for the BYOK VNet.')
param vnetCidr string = '10.60.0.0/16'

@description('APIM SKU. Developer for pilot, Premium for production.')
@allowed([
  'Developer'
  'Premium'
])
param apimSku string = 'Developer'

@description('APIM publisher email shown on the dev portal and notifications.')
param apimPublisherEmail string

@description('APIM publisher display name.')
param apimPublisherName string = 'Copilot BYOK Gateway'

@description('AOAI model name to deploy.')
param modelName string = 'gpt-4.1'

@description('AOAI model version.')
param modelVersion string = '2025-04-14'

@description('AOAI deployment SKU (capacity unit type).')
@allowed([
  'Standard'
  'GlobalStandard'
  'DataZoneStandard'
])
param modelDeploymentSku string = 'Standard'

@description('AOAI deployment capacity (TPM units of 1000).')
param modelCapacity int = 50

@description('Name of the Copilot deployment exposed via APIM (matches what devs put in COPILOT_MODEL).')
param apimExposedModelName string = 'gpt-4.1'

@description('Deploy the classic Azure OpenAI (kind=OpenAI) backend. Exposed via the APIM legacy path /aoai.')
param deployAoai bool = true

@description('Deploy the Microsoft Foundry (kind=AIServices) backend. The default APIM path /openai routes here.')
param deployFoundry bool = true

@description('Foundry model name. Defaults to the AOAI model so both backends host the same model.')
param foundryModelName string = modelName

@description('Foundry model version.')
param foundryModelVersion string = modelVersion

@description('Foundry deployment SKU (capacity unit type).')
param foundryModelDeploymentSku string = modelDeploymentSku

@description('Foundry deployment capacity (TPM units of 1000).')
param foundryModelCapacity int = modelCapacity

@description('Foundry exposed/deployment name (request body "model"). Defaults to apimExposedModelName.')
param foundryExposedModelName string = apimExposedModelName

@description('Comma-separated model names the default (Foundry) route should pin to the legacy AOAI backend instead. Empty = all traffic to Foundry.')
param aoaiPinnedModels string = ''

@description('Caller credential the APIM gateway requires. subscriptionKey = per-developer APIM subscription key (default, what the customer was sold); jwt = short-lived Entra access token validated by validate-jwt. Switchable per deployment without changing backends.')
@allowed([
  'subscriptionKey'
  'jwt'
])
param authMode string = 'subscriptionKey'

@description('Entra tenant ID that issues developer JWTs.')
param entraTenantId string

@description('Entra app ID URI of the BYOK gateway app (created by scripts/setup-entra). Used in the dev-facing error message; this is what callers pass to --resource.')
param apiAppIdUri string

@description('JWT audience the gateway validates. With v2 access tokens this is the app (client) ID GUID, NOT the api:// URI. From scripts/setup-entra output (appId).')
param apiAudience string

@description('Required scope claim value the JWT must contain.')
param requiredScope string = 'cli.invoke'

@description('In subscriptionKey mode, create ready-to-use APIM subscriptions so the gateway can be verified immediately. Ignored when authMode=jwt.')
param deployTestSubscriptions bool = true

@description('Test developer APIM subscriptions to create (subscriptionKey mode). Each { name, product } scopes a key to a rate-limit product tier and is stamped onto telemetry as the developer. product must match a productTiers name.')
param testSubscriptions array = [
  {
    name: 'dev1'
    product: 'byok-standard'
  }
  {
    name: 'dev2'
    product: 'byok-power'
  }
]

@description('Rate-limit product tiers (subscriptionKey mode). Each becomes a published APIM product with a product-scope throttle policy: callsPerMinute (burst), tokensPerMinute (the AI-cost guard), monthlyCallQuota (hard 30-day call ceiling). Group developers by assigning their subscription to a tier.')
param productTiers array = [
  {
    name: 'byok-standard'
    displayName: 'BYOK Standard'
    description: 'Standard developer tier: modest burst + TPM, suitable for typical interactive coding use.'
    callsPerMinute: 60
    tokensPerMinute: 20000
    monthlyCallQuota: 50000
  }
  {
    name: 'byok-power'
    displayName: 'BYOK Power'
    description: 'Power developer tier: higher burst + TPM for heavy agentic / batch use.'
    callsPerMinute: 120
    tokensPerMinute: 60000
    monthlyCallQuota: 200000
  }
]

@description('jwt mode: the SINGLE flat per-developer burst limit (calls/min), keyed on Entra oid. Applies only when authMode=jwt; subscriptionKey mode uses productTiers instead.')
param jwtDefaultCallsPerMinute int = 120

@description('jwt mode: the SINGLE flat per-developer token-per-minute limit (prompt+completion), keyed on Entra oid. The real AI-cost guard. Applies only when authMode=jwt.')
param jwtDefaultTokensPerMinute int = 60000

@description('jwt mode: the SINGLE flat per-developer hard monthly call ceiling (calls per 30 days), keyed on Entra oid. Applies only when authMode=jwt.')
param jwtDefaultMonthlyCallQuota int = 200000

@description('Content-filter (responsible-AI) policy name applied to model deployments. Microsoft.DefaultV2 = built-in default (no change). Set to a custom raiPolicy name created via scripts/configure-content-filter to tighten/loosen filtering.')
param raiPolicyName string = 'Microsoft.DefaultV2'

@description('Deploy a P2S VPN gateway. Adds ~30 min and ~$140/mo.')
param deployVpnGateway bool = true

@description('VPN root cert public data (base64, single line, no PEM headers). Required if deployVpnGateway=true.')
@secure()
param vpnRootCertPublicData string = ''

@description('Optional: resource ID of an existing VNet to peer with. Empty = no peering.')
param peerVnetResourceId string = ''

@description('Principal ID (object ID) to grant deployer-level RBAC on AOAI. Leave empty to skip.')
param deployerPrincipalId string = ''

@description('Assign the "Cognitive Services OpenAI User" role to APIM MI on the AOAI account. Requires the deployer to have Microsoft.Authorization/roleAssignments/write. Set false to assign out-of-band.')
param assignAoaiRbac bool = true

@description('Object IDs (users or groups) to grant "Cognitive Services OpenAI User" on BOTH the AOAI and Foundry accounts, enabling direct portal/playground + SDK access. Accounts have local auth disabled, so this is the ONLY way humans reach the data plane. Empty = none (add users out-of-band).')
param playgroundPrincipalIds array = []

@description('Principal type for playgroundPrincipalIds: "User" for individuals, "Group" for an Entra security group.')
@allowed([ 'User', 'Group' ])
param playgroundPrincipalType string = 'User'

@description('Deploy a Windows test VM + Azure Bastion for manual in-VNet validation of the Internal APIM. Tear down when done.')
param deployTestVm bool = false
@description('Admin username for the test VM. Required if deployTestVm=true.')
param testVmAdminUsername string = 'byokadmin'

@description('Admin password for the test VM. Required if deployTestVm=true. Passed at deploy time, never stored.')
@secure()
param testVmAdminPassword string = ''

@description('Deploy a VNet-linked Private DNS zone (azure-api.us/.net) with an A record for the APIM gateway so in-VNet clients resolve it without a hosts entry. Prerequisite for the VPN/DNS-resolver phase too.')
param deployApimPrivateDns bool = true

var suffix = substring(uniqueString(subscription().id, envName, location), 0, 6)
var rgName = 'rg-${namePrefix}-${envName}'

var cloudVars = {
  AzureCloud: {
    aoaiDnsZone: 'privatelink.openai.azure.com'
    cognitiveDnsZone: 'privatelink.cognitiveservices.azure.com'
    aiDnsZone: 'privatelink.services.ai.azure.com'
    aoaiAudience: 'https://cognitiveservices.azure.com'
    foundryAudience: 'https://cognitiveservices.azure.com'
    aoaiPublicSuffix: 'openai.azure.com'
    #disable-next-line no-hardcoded-env-urls // intentional per-cloud constant, not the active env
    entraLoginHost: 'login.microsoftonline.com'
    apimDnsZone: 'azure-api.net'
  }
  AzureUSGovernment: {
    aoaiDnsZone: 'privatelink.openai.azure.us'
    cognitiveDnsZone: 'privatelink.cognitiveservices.azure.us'
    aiDnsZone: '' // services.ai privatelink zone is Commercial-only today
    aoaiAudience: 'https://cognitiveservices.azure.us'
    foundryAudience: 'https://cognitiveservices.azure.us'
    aoaiPublicSuffix: 'openai.azure.us'
    entraLoginHost: 'login.microsoftonline.us'
    apimDnsZone: 'azure-api.us'
  }
}

var v = cloudVars[cloudEnv]
var entraOpenIdConfigUrl = 'https://${v.entraLoginHost}/${entraTenantId}/v2.0/.well-known/openid-configuration'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

module observability 'modules/observability.bicep' = {
  name: 'observability'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
  }
}

module network 'modules/network.bicep' = {
  name: 'network'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
    vnetCidr: vnetCidr
    deployVpnGateway: deployVpnGateway
    vpnRootCertPublicData: vpnRootCertPublicData
    peerVnetResourceId: peerVnetResourceId
    deployTestVm: deployTestVm
  }
}

module privatedns 'modules/privatedns-cognitive.bicep' = {
  name: 'privatedns-cognitive'
  scope: rg
  params: {
    openaiDnsZoneName: v.aoaiDnsZone
    cognitiveDnsZoneName: v.cognitiveDnsZone
    aiDnsZoneName: v.aiDnsZone
    vnetId: network.outputs.vnetId
    peerVnetResourceId: peerVnetResourceId
  }
}

module aoai 'modules/aoai.bicep' = if (deployAoai) {
  name: 'aoai'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
    openaiPublicSuffix: v.aoaiPublicSuffix
    openaiZoneId: privatedns.outputs.openaiZoneId
    peSubnetId: network.outputs.peSubnetId
    modelName: modelName
    modelVersion: modelVersion
    modelDeploymentSku: modelDeploymentSku
    modelCapacity: modelCapacity
    apimExposedModelName: apimExposedModelName
    raiPolicyName: raiPolicyName
  }
}

module foundry 'modules/foundry.bicep' = if (deployFoundry) {
  name: 'foundry'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
    openaiPublicSuffix: v.aoaiPublicSuffix
    openaiZoneId: privatedns.outputs.openaiZoneId
    cognitiveZoneId: privatedns.outputs.cognitiveZoneId
    aiZoneId: privatedns.outputs.aiZoneId
    peSubnetId: network.outputs.peSubnetId
    modelName: foundryModelName
    modelVersion: foundryModelVersion
    modelDeploymentSku: foundryModelDeploymentSku
    modelCapacity: foundryModelCapacity
    exposedModelName: foundryExposedModelName
    raiPolicyName: raiPolicyName
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
    apimSku: apimSku
    apimPublisherEmail: apimPublisherEmail
    apimPublisherName: apimPublisherName
    apimSubnetId: network.outputs.apimSubnetId
    appInsightsId: observability.outputs.appInsightsId
    appInsightsInstrumentationKey: observability.outputs.appInsightsInstrumentationKey
    logAnalyticsId: observability.outputs.logAnalyticsId
  }
}

module apimNamedValues 'modules/apim-named-values.bicep' = {
  name: 'apim-named-values'
  scope: rg
  params: {
    apimName: apim.outputs.apimName
    entraOpenIdConfigUrl: entraOpenIdConfigUrl
    apiAppIdUri: apiAppIdUri
    apiAudience: apiAudience
    requiredScope: requiredScope
    #disable-next-line BCP318 // guarded by deployAoai; '' when the module is not deployed
    aoaiPrivateBaseUrl: deployAoai ? aoai.outputs.aoaiPrivateBaseUrl : ''
    aoaiAudience: v.aoaiAudience
    #disable-next-line BCP318 // guarded by deployFoundry; '' when the module is not deployed
    foundryPrivateBaseUrl: deployFoundry ? foundry.outputs.foundryPrivateBaseUrl : ''
    foundryAudience: v.foundryAudience
    aoaiPinnedModels: aoaiPinnedModels
    jwtCallsPerMinute: jwtDefaultCallsPerMinute
    jwtTokensPerMinute: jwtDefaultTokensPerMinute
    jwtMonthlyCallQuota: jwtDefaultMonthlyCallQuota
  }
}

module apimFoundryApi 'modules/apim-foundry-api.bicep' = if (deployFoundry) {
  name: 'apim-foundry-api'
  scope: rg
  params: {
    apimName: apim.outputs.apimName
    #disable-next-line BCP318 // guarded by the module's own if (deployFoundry)
    foundryPrivateBaseUrl: deployFoundry ? foundry.outputs.foundryPrivateBaseUrl : ''
    authMode: authMode
    namedValueIds: apimNamedValues.outputs.namedValueIds
  }
  // The Foundry API uses path 'openai'. On environments upgraded from an earlier layout the
  // AOAI API may still occupy 'openai' before it is re-pathed to 'aoai'; deploy AOAI first so
  // 'openai' is free, avoiding "Cannot create API ... with the same Path" collisions.
  dependsOn: [
    apimAoaiApi
  ]
}

module apimAoaiApi 'modules/apim-aoai-api.bicep' = if (deployAoai) {
  name: 'apim-aoai-api'
  scope: rg
  params: {
    apimName: apim.outputs.apimName
    #disable-next-line BCP318 // guarded by the module's own if (deployAoai)
    aoaiPrivateBaseUrl: deployAoai ? aoai.outputs.aoaiPrivateBaseUrl : ''
    authMode: authMode
    namedValueIds: apimNamedValues.outputs.namedValueIds
  }
}

module apimProducts 'modules/apim-products.bicep' = if (authMode == 'subscriptionKey' && deployTestSubscriptions) {
  name: 'apim-products'
  scope: rg
  params: {
    apimName: apim.outputs.apimName
    productTiers: productTiers
    apiNames: concat(
      deployFoundry ? [ 'copilot-byok-foundry' ] : [],
      deployAoai ? [ 'copilot-byok-aoai' ] : []
    )
  }
  // Products link the APIs, so order after the API modules exist.
  dependsOn: [
    apimFoundryApi
    apimAoaiApi
  ]
}

module apimSubscriptions 'modules/apim-subscriptions.bicep' = if (authMode == 'subscriptionKey' && deployTestSubscriptions) {
  name: 'apim-subscriptions'
  scope: rg
  params: {
    apimName: apim.outputs.apimName
    subscriptions: testSubscriptions
  }
  // Order after the products so each subscription's product scope binds to an existing product.
  dependsOn: [
    apimProducts
  ]
}

module rbac 'modules/rbac.bicep' = if (assignAoaiRbac || !empty(playgroundPrincipalIds)) {
  name: 'rbac'
  scope: rg
  params: {
    #disable-next-line BCP318 // guarded by deployAoai; '' when the module is not deployed
    aoaiAccountName: deployAoai ? aoai.outputs.aoaiAccountName : ''
    #disable-next-line BCP318 // guarded by deployFoundry; '' when the module is not deployed
    foundryAccountName: deployFoundry ? foundry.outputs.foundryAccountName : ''
    assignAoai: deployAoai
    assignFoundry: deployFoundry
    assignApimMi: assignAoaiRbac
    playgroundPrincipalIds: playgroundPrincipalIds
    playgroundPrincipalType: playgroundPrincipalType
    apimPrincipalId: apim.outputs.apimPrincipalId
    deployerPrincipalId: deployerPrincipalId
  }
}

module testvm 'modules/testvm.bicep' = if (deployTestVm) {
  name: 'testvm'
  scope: rg
  params: {
    namePrefix: namePrefix
    envName: envName
    suffix: suffix
    location: location
    vmSubnetId: network.outputs.vmSubnetId
    adminUsername: testVmAdminUsername
    adminPassword: testVmAdminPassword
  }
}

module apimPrivateDns 'modules/apim-private-dns.bicep' = if (deployApimPrivateDns) {
  name: 'apim-private-dns'
  scope: rg
  params: {
    apimDnsZone: v.apimDnsZone
    apimGatewayHost: apim.outputs.apimGatewayHost
    apimPrivateIp: apim.outputs.apimPrivateIp
    vnetId: network.outputs.vnetId
    suffix: suffix
  }
}

output resourceGroup string = rg.name
output apimName string = apim.outputs.apimName
output apimGatewayUrl string = apim.outputs.apimGatewayUrl
#disable-next-line BCP318 // guarded by deployAoai
output aoaiAccountName string = deployAoai ? aoai.outputs.aoaiAccountName : ''
#disable-next-line BCP318 // guarded by deployAoai
output aoaiPrivateFqdn string = deployAoai ? aoai.outputs.aoaiPrivateFqdn : ''
#disable-next-line BCP318 // guarded by deployFoundry
output foundryAccountName string = deployFoundry ? foundry.outputs.foundryAccountName : ''
#disable-next-line BCP318 // guarded by deployFoundry
output foundryPrivateFqdn string = deployFoundry ? foundry.outputs.foundryPrivateFqdn : ''
output vnetName string = network.outputs.vnetName
output appInsightsName string = observability.outputs.appInsightsName
output entraOpenIdConfigUrl string = entraOpenIdConfigUrl

@description('Test APIM subscription IDs created in subscriptionKey mode. Fetch each key: az apim subscription show -g <rg> --service-name <apim> --sid <id> --query primaryKey -o tsv')
#disable-next-line BCP318 // guarded by the same condition as the module's if()
output testSubscriptionIds array = (authMode == 'subscriptionKey' && deployTestSubscriptions) ? apimSubscriptions.outputs.subscriptionIds : []
