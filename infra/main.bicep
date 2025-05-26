@minLength(5)
param appName string
param appImage string
param appPort string

param location string = resourceGroup().location

param acrSku string = 'Basic'
param keyVaultSkuName string = 'standard'
param logAnalyticsSku string = 'PerGB2018'

// Tags for resources
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
    retentionInDays: 30
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
      activeRevisionsMode: 'Single'
      ingress: {
        allowInsecure: false    // secure traffic only
        clientCertificateMode: 'Ignore'
        external: true
        targetPort: int(appPort)
        transport: 'http'
        traffic: [
          {
            weight: 100         // 100% of traffic to the latest revision
            latestRevision: true
          }
        ]      
      }
      maxInactiveRevisions: 10
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
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 3
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
