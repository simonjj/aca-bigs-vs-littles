@description('Name of the azd environment.')
param environmentName string

@description('Azure region for both isolated benchmark environments.')
param location string = 'southcentralus'

@description('Tags applied to resources.')
param tags object = {}

var normalizedEnvironmentName = take(toLower(replace(environmentName, '_', '-')), 12)
var namePrefix = 'lvb-${normalizedEnvironmentName}'
var uniqueToken = toLower(uniqueString(subscription().id, resourceGroup().id, environmentName))
var compactPrefix = toLower(replace(namePrefix, '-', ''))
var acrName = take('${compactPrefix}${uniqueToken}', 50)
var littlesStorageName = take('st${compactPrefix}lit${uniqueToken}', 24)
var bigsStorageName = take('st${compactPrefix}big${uniqueToken}', 24)
var logAnalyticsName = 'law-${namePrefix}-${uniqueToken}'
var littlesEnvironmentName = 'cae-${namePrefix}-littles'
var bigsEnvironmentName = 'cae-${namePrefix}-bigs'
var pullIdentityName = 'id-${namePrefix}-acr-pull'
var loadTestingName = take('lt-${namePrefix}-${uniqueToken}', 64)

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    retentionInDays: 30
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: acrName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: pullIdentityName
  location: location
  tags: tags
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, pullIdentity.id, 'AcrPull')
  scope: acr
  properties: {
    principalId: pullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource littlesVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${namePrefix}-littles'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.20.0.0/21'
      ]
    }
    subnets: [
      {
        name: 'aca-infrastructure'
        properties: {
          addressPrefix: '10.20.0.0/23'
          delegations: [
            {
              name: 'container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource bigsVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-${namePrefix}-bigs'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.40.0.0/21'
      ]
    }
    subnets: [
      {
        name: 'aca-infrastructure'
        properties: {
          addressPrefix: '10.40.0.0/23'
          delegations: [
            {
              name: 'container-apps'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

var workloadProfiles = [
  {
    name: 'Consumption'
    workloadProfileType: 'Consumption'
  }
  {
    name: 'Flex'
    workloadProfileType: 'Flex'
  }
  {
    name: 'Ingress-D4'
    workloadProfileType: 'D4'
    minimumCount: 2
    maximumCount: 2
  }
]

var ingressConfiguration = {
  workloadProfileName: 'Ingress-D4'
  terminationGracePeriodSeconds: 500
  headerCountLimit: 100
  requestIdleTimeout: 4
}

resource littlesEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: littlesEnvironmentName
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    ingressConfiguration: ingressConfiguration
    vnetConfiguration: {
      infrastructureSubnetId: littlesVnet.properties.subnets[0].id
      internal: false
    }
    workloadProfiles: workloadProfiles
    zoneRedundant: false
  }
}

resource bigsEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: bigsEnvironmentName
  location: location
  tags: tags
  dependsOn: [
    littlesEnvironment
  ]
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    ingressConfiguration: ingressConfiguration
    vnetConfiguration: {
      infrastructureSubnetId: bigsVnet.properties.subnets[0].id
      internal: false
    }
    workloadProfiles: workloadProfiles
    zoneRedundant: false
  }
}

resource littlesStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: littlesStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource littlesBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: littlesStorage
  name: 'default'
}

resource littlesUpstreamContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: littlesBlobService
  name: 'upstream'
  properties: {
    publicAccess: 'None'
  }
}

resource bigsStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: bigsStorageName
  location: location
  tags: tags
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
    supportsHttpsTrafficOnly: true
  }
}

resource bigsBlobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: bigsStorage
  name: 'default'
}

resource bigsUpstreamContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: bigsBlobService
  name: 'upstream'
  properties: {
    publicAccess: 'None'
  }
}

resource loadTesting 'Microsoft.LoadTestService/loadTests@2022-12-01' = {
  name: loadTestingName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

output namePrefix string = namePrefix
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output pullIdentityName string = pullIdentity.name
output littlesEnvironmentName string = littlesEnvironment.name
output bigsEnvironmentName string = bigsEnvironment.name
output littlesStorageName string = littlesStorage.name
output bigsStorageName string = bigsStorage.name
output littlesUpstreamUrl string = '${littlesStorage.properties.primaryEndpoints.blob}upstream/payload.json'
output bigsUpstreamUrl string = '${bigsStorage.properties.primaryEndpoints.blob}upstream/payload.json'
output loadTestingName string = loadTesting.name
