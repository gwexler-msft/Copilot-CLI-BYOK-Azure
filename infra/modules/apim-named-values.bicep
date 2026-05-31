// All APIM named values created ONCE, service-scoped, so both the Foundry (default) API and
// the AOAI (legacy) API can reference them via {{...}} in their policies without collisions.

param apimName string

param entraOpenIdConfigUrl string
param apiAppIdUri string
param apiAudience string
param requiredScope string

@description('Default api-version APIM injects when caller omits it.')
param defaultAoaiApiVersion string = '2024-10-21'

@description('Private base URL of the classic AOAI (kind=OpenAI) account. Empty when AOAI not deployed.')
param aoaiPrivateBaseUrl string = ''

@description('MI token audience for the AOAI backend (e.g. https://cognitiveservices.azure.us).')
param aoaiAudience string = ''

@description('Private base URL of the Foundry (kind=AIServices) account. Empty when Foundry not deployed.')
param foundryPrivateBaseUrl string = ''

@description('MI token audience for the Foundry OpenAI-compat backend (same as AOAI: cognitiveservices.azure.*).')
param foundryAudience string = ''

@description('Comma-separated model names that the DEFAULT (Foundry) route should pin to the AOAI backend instead. Empty = everything goes to Foundry.')
param aoaiPinnedModels string = ''

@description('jwt mode: per-developer burst limit (calls/min) keyed on Entra oid.')
param jwtCallsPerMinute int = 120

@description('jwt mode: per-developer token-per-minute limit (prompt+completion) keyed on Entra oid. The real AI-cost guard.')
param jwtTokensPerMinute int = 60000

@description('jwt mode: per-developer hard monthly call ceiling (calls per 30 days) keyed on Entra oid.')
param jwtMonthlyCallQuota int = 200000

resource apim 'Microsoft.ApiManagement/service@2024-05-01' existing = {
  name: apimName
}

resource nvOpenId 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'entra-openid-config-url'
  properties: {
    displayName: 'entra-openid-config-url'
    value: entraOpenIdConfigUrl
    secret: false
  }
}

resource nvAppIdUri 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'api-app-id-uri'
  properties: {
    displayName: 'api-app-id-uri'
    value: apiAppIdUri
    secret: false
  }
}

resource nvAudience 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'api-audience'
  properties: {
    displayName: 'api-audience'
    value: apiAudience
    secret: false
  }
}

resource nvScope 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'required-scope'
  properties: {
    displayName: 'required-scope'
    value: requiredScope
    secret: false
  }
}

resource nvApiVersion 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'aoai-default-api-version'
  properties: {
    displayName: 'aoai-default-api-version'
    value: defaultAoaiApiVersion
    secret: false
  }
}

resource nvAoaiBase 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'aoai-private-base-url'
  properties: {
    displayName: 'aoai-private-base-url'
    value: empty(aoaiPrivateBaseUrl) ? 'https://unset.invalid' : aoaiPrivateBaseUrl
    secret: false
  }
}

resource nvAoaiMiAud 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'aoai-mi-audience'
  properties: {
    displayName: 'aoai-mi-audience'
    value: empty(aoaiAudience) ? 'https://unset.invalid' : aoaiAudience
    secret: false
  }
}

resource nvFoundryBase 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'foundry-private-base-url'
  properties: {
    displayName: 'foundry-private-base-url'
    value: empty(foundryPrivateBaseUrl) ? 'https://unset.invalid' : foundryPrivateBaseUrl
    secret: false
  }
}

resource nvFoundryMiAud 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'foundry-mi-audience'
  properties: {
    displayName: 'foundry-mi-audience'
    value: empty(foundryAudience) ? 'https://unset.invalid' : foundryAudience
    secret: false
  }
}

resource nvPinnedModels 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'aoai-pinned-models'
  properties: {
    displayName: 'aoai-pinned-models'
    value: empty(aoaiPinnedModels) ? ' ' : aoaiPinnedModels
    secret: false
  }
}

resource nvJwtCalls 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'jwt-calls-per-minute'
  properties: {
    displayName: 'jwt-calls-per-minute'
    value: string(jwtCallsPerMinute)
    secret: false
  }
}

resource nvJwtTokens 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'jwt-tokens-per-minute'
  properties: {
    displayName: 'jwt-tokens-per-minute'
    value: string(jwtTokensPerMinute)
    secret: false
  }
}

resource nvJwtQuota 'Microsoft.ApiManagement/service/namedValues@2024-05-01' = {
  parent: apim
  name: 'jwt-monthly-call-quota'
  properties: {
    displayName: 'jwt-monthly-call-quota'
    value: string(jwtMonthlyCallQuota)
    secret: false
  }
}

output namedValueIds array = [
  nvOpenId.id
  nvAppIdUri.id
  nvAudience.id
  nvScope.id
  nvApiVersion.id
  nvAoaiBase.id
  nvAoaiMiAud.id
  nvFoundryBase.id
  nvFoundryMiAud.id
  nvPinnedModels.id
  nvJwtCalls.id
  nvJwtTokens.id
  nvJwtQuota.id
]
