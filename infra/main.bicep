targetScope = 'subscription'

@description('Name of the azd environment.')
@minLength(1)
param environmentName string

@description('Azure region for both isolated benchmark environments.')
param location string = 'southcentralus'

@description('Container image used by the Littles app. Bicep uses a first-deployment placeholder; the postprovision hook restores an existing deployed image.')
param littlesImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Container image used by the Bigs app. Bicep uses a first-deployment placeholder; the postprovision hook restores an existing deployed image.')
param bigsImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@description('Additional tags applied to resources.')
param tags object = {}

var normalizedEnvironmentName = take(toLower(replace(environmentName, '_', '-')), 24)
var resourceGroupName = 'rg-aca-lvb-${normalizedEnvironmentName}'
var benchmarkTags = union(tags, {
  'azd-env-name': environmentName
  project: 'aca-bigs-vs-littles'
})

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-11-01' = {
  name: resourceGroupName
  location: location
  tags: benchmarkTags
}

module platform 'platform.bicep' = {
  name: 'platform'
  scope: resourceGroup
  params: {
    environmentName: environmentName
    location: location
    tags: benchmarkTags
  }
}

module apps 'apps.bicep' = {
  name: 'apps'
  scope: resourceGroup
  params: {
    location: location
    environmentName: environmentName
    namePrefix: platform.outputs.namePrefix
    tags: benchmarkTags
    littlesEnvironmentName: platform.outputs.littlesEnvironmentName
    bigsEnvironmentName: platform.outputs.bigsEnvironmentName
    pullIdentityName: platform.outputs.pullIdentityName
    acrLoginServer: platform.outputs.acrLoginServer
    littlesImage: littlesImage
    bigsImage: bigsImage
    littlesUpstreamUrl: platform.outputs.littlesUpstreamUrl
    bigsUpstreamUrl: platform.outputs.bigsUpstreamUrl
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = platform.outputs.acrLoginServer
output AZURE_CONTAINER_REGISTRY_NAME string = platform.outputs.acrName
output LITTLES_APP_NAME string = apps.outputs.littlesAppName
output BIGS_APP_NAME string = apps.outputs.bigsAppName
output LITTLES_ENVIRONMENT_NAME string = platform.outputs.littlesEnvironmentName
output BIGS_ENVIRONMENT_NAME string = platform.outputs.bigsEnvironmentName
output LITTLES_STORAGE_NAME string = platform.outputs.littlesStorageName
output BIGS_STORAGE_NAME string = platform.outputs.bigsStorageName
output LITTLES_UPSTREAM_BASE_URL string = platform.outputs.littlesUpstreamUrl
output BIGS_UPSTREAM_BASE_URL string = platform.outputs.bigsUpstreamUrl
output LOAD_TESTING_NAME string = platform.outputs.loadTestingName
output LITTLES_FQDN string = apps.outputs.littlesFqdn
output BIGS_FQDN string = apps.outputs.bigsFqdn
output SERVICE_LITTLES_ENDPOINT_URL string = 'https://${apps.outputs.littlesFqdn}'
output SERVICE_BIGS_ENDPOINT_URL string = 'https://${apps.outputs.bigsFqdn}'
