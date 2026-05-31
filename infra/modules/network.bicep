param namePrefix string
param envName string
param suffix string
param location string
param vnetCidr string
param deployVpnGateway bool

@secure()
param vpnRootCertPublicData string

param peerVnetResourceId string

@description('Deploy a test VM + Azure Bastion for manual in-VNet validation of the Internal APIM.')
param deployTestVm bool = false

var vnetName       = take('vnet-${namePrefix}-${envName}-${suffix}', 64)
var nsgApimName    = take('nsg-${namePrefix}-apim-${envName}-${suffix}', 64)
var vpnGwName      = take('vpngw-${namePrefix}-${envName}-${suffix}', 80)
var vpnPipName     = take('pip-vpngw-${namePrefix}-${envName}-${suffix}', 80)
var p2sAddressPool = '172.16.200.0/24'

resource nsgApim 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: nsgApimName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-Management'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'Allow-AzureLB'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
      {
        name: 'Allow-VNet-Inbound-HTTPS'
        properties: {
          priority: 120
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

var baseSubnets = [
  {
    name: 'snet-apim'
    properties: {
      addressPrefix: '10.60.1.0/27'
      networkSecurityGroup: { id: nsgApim.id }
      privateEndpointNetworkPolicies: 'Enabled'
    }
  }
  {
    name: 'snet-pe'
    properties: {
      addressPrefix: '10.60.2.0/24'
      privateEndpointNetworkPolicies: 'Disabled'
    }
  }
  {
    name: 'snet-dns-in'
    properties: {
      addressPrefix: '10.60.3.0/28'
      delegations: [
        {
          name: 'Microsoft.Network.dnsResolvers'
          properties: { serviceName: 'Microsoft.Network/dnsResolvers' }
        }
      ]
    }
  }
]

var gatewaySubnet = [
  {
    name: 'GatewaySubnet'
    properties: { addressPrefix: '10.60.255.0/27' }
  }
]

var testVmSubnets = [
  {
    name: 'snet-vm'
    properties: { addressPrefix: '10.60.5.0/27' }
  }
  {
    name: 'AzureBastionSubnet'
    properties: { addressPrefix: '10.60.6.0/26' }
  }
]

var optionalSubnets = concat(
  deployVpnGateway ? gatewaySubnet : [],
  deployTestVm ? testVmSubnets : []
)

resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [vnetCidr] }
    subnets: concat(baseSubnets, optionalSubnets)
  }
}

resource vpnPip 'Microsoft.Network/publicIPAddresses@2024-01-01' = if (deployVpnGateway) {
  name: vpnPipName
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource vpnGw 'Microsoft.Network/virtualNetworkGateways@2024-01-01' = if (deployVpnGateway) {
  name: vpnGwName
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: { name: 'VpnGw1', tier: 'VpnGw1' }
    activeActive: false
    enableBgp: false
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: { id: vpnPip.id }
          subnet: { id: '${vnet.id}/subnets/GatewaySubnet' }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: { addressPrefixes: [p2sAddressPool] }
      vpnClientProtocols: ['OpenVPN']
      vpnAuthenticationTypes: ['Certificate']
      vpnClientRootCertificates: empty(vpnRootCertPublicData) ? [] : [
        {
          name: 'P2SRootCert'
          properties: { publicCertData: vpnRootCertPublicData }
        }
      ]
    }
  }
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-01-01' = if (!empty(peerVnetResourceId)) {
  parent: vnet
  name: 'to-peer'
  properties: {
    remoteVirtualNetwork: { id: peerVnetResourceId }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output apimSubnetId string = '${vnet.id}/subnets/snet-apim'
output peSubnetId   string = '${vnet.id}/subnets/snet-pe'
output gatewaySubnetId string = deployVpnGateway ? '${vnet.id}/subnets/GatewaySubnet' : ''
output vmSubnetId string = deployTestVm ? '${vnet.id}/subnets/snet-vm' : ''
output bastionSubnetId string = deployTestVm ? '${vnet.id}/subnets/AzureBastionSubnet' : ''
