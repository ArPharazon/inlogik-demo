@minLength(5)
param appName string

@description('The image to deploy in the container app. Must be in the format: <acr-name>.azurecr.io/<image-name>:<tag>')
param appImage string

@description('The port on which the application listens. Must be a valid port number (1-65535).')
param appPort string

@description('Location for all resources')
param location string = resourceGroup().location

@allowed([
  'Basic'
  'Classic'
  'Premium'
  'Standard'
])
param acrSku string = 'Basic'

@description('Number of CPU cores the container can use. Can be with a maximum of two decimals.')
@allowed([
  '0.25'
  '0.5'
  '0.75'
  '1'
  '1.25'
  '1.5'
  '1.75'
  '2'
])
param cpuCore string = '0.5'

@description('Amount of memory (in gibibytes, GiB) allocated to the container up to 4GiB. Can be with a maximum of two decimals. Ratio with CPU cores must be equal to 2.')
@allowed([
  '0.5'
  '1'
  '1.5'
  '2'
  '3'
  '3.5'
  '4'
])
param memorySize string = '1'

@description('Minimum number of replicas that will be deployed')
@minValue(0)
@maxValue(3)
param minReplicas int = 0

@description('Maximum number of replicas that will be deployed')
@minValue(0)
@maxValue(25)
param maxReplicas int = 3

@description('The SKU for the Key Vault. Default is Standard.')
@allowed([
  'standard'
  'premium'
])
param keyVaultSkuName string = 'standard'

@description('The SKU for the Log Analytics Workspace. Default is PerGB2018.')
@allowed([
  'PerGB2018'
  'PerNode'
  'Free'
])
param logAnalyticsSku string = 'PerGB2018'

@description('Number of days to retain logs in Log Analytics Workspace. Default is 30 days.')
@minValue(7)
param logAnalyticsRetentionDays int = 30

@description('Maximum number of concurrent requests per replica for scaling')
@minValue(10)
@maxValue(1000)
param maxConcurrentRequests int = 100

@description('Tags to apply to all resources')
var tags = {
  environment: 'production'
  description: 'container-apps-demo'
}



// note: using the built-in role definitions
// see: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/containers#acrpull
resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '7f951dda-4ed3-4680-a7ca-43fe172d538d' // AcrPull role definition ID
}

// see: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli
resource keyVaultCertificateUserRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '4633458b-17de-408a-b874-0445c86b69e6'
}

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: '${appName}-kv'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: keyVaultSkuName
    }
    // Use RBAC, do not specify accessPolicies
    enableRbacAuthorization: true
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableSoftDelete: true
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
  }
}

// Container Registry
resource acr 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: '${appName}acr'
  location: location
  sku: {
    name: acrSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    adminUserEnabled: true
  }
}

resource registryCredentialsSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'acr-username'
  properties: {
    value: acr.listCredentials().username
  }
}

resource registryPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'acr-password'
  properties: {
    value: !empty(acr.listCredentials().passwords) ? first(acr.listCredentials().passwords).value : ''
  }
}

// Log Analytics Workspace
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: '${appName}-log'
  location: location
  tags: tags
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: logAnalyticsRetentionDays
  }
}

resource logAnalyticsWorkspaceId 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'loganalytics-workspace-id'
  properties: {
    value: logAnalytics.id
  }
}

resource logAnalyticsPrimaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'loganalytics-primary-key'
  properties: {
    value: logAnalytics.listKeys().primarySharedKey
  }
}

resource logAnalyticsSecondaryKeySecret 'Microsoft.KeyVault/vaults/secrets@2024-11-01' = {
  parent: keyVault
  name: 'loganalytics-secondary-key'
  properties: {
    value: logAnalytics.listKeys().secondarySharedKey
  }
}

// Application Insights
resource appInsights 'microsoft.insights/components@2020-02-02' = {
  name: '${appName}-ain'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    RetentionInDays: 90
    WorkspaceResourceId: logAnalytics.id
  }
}


// Managed Environment for Container Apps
resource managedEnv 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: '${appName}-env'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: false
  }
}

// Managed Environment role assignment: 'Key Vault Certificate User' (to retrieve any certs)
resource managedEnvKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, managedEnv.id, keyVaultCertificateUserRoleDefinition.id) 
  properties: {
    roleDefinitionId: keyVaultCertificateUserRoleDefinition.id
    principalId: managedEnv.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2025-01-01' = {
  name: '${appName}-app'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    environmentId: managedEnv.id
    configuration: {
      activeRevisionsMode: 'Multiple' // for blue-green deployments
      ingress: {
        allowInsecure: false    // secure traffic only
        clientCertificateMode: 'Ignore'
        external: true
        targetPort: int(appPort)
        transport: 'http'
      }
    }
    template: {
      containers: [
        {
          name: '${appName}-app'
          image: appImage
          env: [
            {
              name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
              value: appInsights.properties.InstrumentationKey
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: appInsights.properties.ConnectionString
            }
          ]
          resources: {
            cpu: json(cpuCore)
            memory: '${memorySize}Gi'
          }
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-scale-rule'
            http: {
              metadata: {
                concurrentRequests: '${maxConcurrentRequests}'
              }
            }
          }
        ]
      }
    }
  }
}

// Role assignment for the Container App to pull images from ACR
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: acr
  name: guid(acr.id, containerApp.id, acrPullRoleDefinition.id)
  properties: {
    principalId: containerApp.identity.principalId
    roleDefinitionId: acrPullRoleDefinition.id
    principalType: 'ServicePrincipal'
  }
}
