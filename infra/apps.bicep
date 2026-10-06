@description('Azure region for the benchmark environments.')
param location string = 'southcentralus'

param environmentName string
param namePrefix string
param tags object = {}
param littlesEnvironmentName string
param bigsEnvironmentName string
param pullIdentityName string
param acrLoginServer string
param littlesImage string
param bigsImage string
@secure()
param littlesUpstreamUrl string

@secure()
param bigsUpstreamUrl string

resource littlesEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' existing = {
  name: littlesEnvironmentName
}

resource bigsEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' existing = {
  name: bigsEnvironmentName
}

resource pullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: pullIdentityName
}

var registryConfiguration = [
  {
    server: acrLoginServer
    identity: pullIdentity.id
  }
]

var appIdentity = {
  type: 'UserAssigned'
  userAssignedIdentities: {
    '${pullIdentity.id}': {}
  }
}

resource littlesApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: 'ca-${namePrefix}-littles'
  location: location
  tags: union(tags, {
    'azd-env-name': environmentName
    'azd-service-name': 'littles'
  })
  identity: appIdentity
  properties: {
    managedEnvironmentId: littlesEnvironment.id
    workloadProfileName: 'Flex'
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'upstream-url'
          value: littlesUpstreamUrl
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: registryConfiguration
    }
    template: {
      containers: [
        {
          name: 'simulation'
          image: littlesImage
          env: [
            {
              name: 'UPSTREAM_URL'
              secretRef: 'upstream-url'
            }
            {
              name: 'WAIT_MS'
              value: '40'
            }
            {
              name: 'UPSTREAM_TIMEOUT_MS'
              value: '5000'
            }
          ]
          resources: {
            cpu: json('0.5')
            memory: '2Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 1
              periodSeconds: 2
              failureThreshold: 30
              timeoutSeconds: 2
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 3000
              }
              periodSeconds: 10
              failureThreshold: 3
              timeoutSeconds: 2
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 2
            }
          ]
        }
      ]
      scale: {
        minReplicas: 32
        maxReplicas: 32
        rules: []
      }
    }
  }
}

resource bigsApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: 'ca-${namePrefix}-bigs'
  location: location
  tags: union(tags, {
    'azd-env-name': environmentName
    'azd-service-name': 'bigs'
  })
  identity: appIdentity
  properties: {
    managedEnvironmentId: bigsEnvironment.id
    workloadProfileName: 'Flex'
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'upstream-url'
          value: bigsUpstreamUrl
        }
      ]
      ingress: {
        external: true
        targetPort: 3000
        transport: 'http'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: registryConfiguration
    }
    template: {
      containers: [
        {
          name: 'simulation'
          image: bigsImage
          env: [
            {
              name: 'UPSTREAM_URL'
              secretRef: 'upstream-url'
            }
            {
              name: 'WAIT_MS'
              value: '40'
            }
            {
              name: 'UPSTREAM_TIMEOUT_MS'
              value: '5000'
            }
          ]
          resources: {
            cpu: json('1')
            memory: '4Gi'
          }
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 3000
              }
              initialDelaySeconds: 1
              periodSeconds: 2
              failureThreshold: 30
              timeoutSeconds: 2
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/ready'
                port: 3000
              }
              periodSeconds: 10
              failureThreshold: 3
              timeoutSeconds: 2
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 3000
              }
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 2
            }
          ]
        }
      ]
      scale: {
        minReplicas: 16
        maxReplicas: 16
        rules: []
      }
    }
  }
}

output littlesFqdn string = littlesApp.properties.configuration.ingress.fqdn
output bigsFqdn string = bigsApp.properties.configuration.ingress.fqdn
output littlesAppName string = littlesApp.name
output bigsAppName string = bigsApp.name
output littlesAppId string = littlesApp.id
output bigsAppId string = bigsApp.id
