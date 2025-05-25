@minLength(5)
param appName string
param appImage string
param appPort string

param location string = resourceGroup().location

param acrSku string = 'Basic'
param keyVaultSkuName string = 'standard'
param logAnalyticsSku string = 'PerGB2018'

// Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: '${appName}-kv'
  location: location
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

// Managed Environment for Container Apps
resource managedEnv 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: '${appName}-env'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
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
// see: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli
resource managedEnvKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, managedEnv.id, 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba') 
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
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
      // registries: [
      //   {
      //     server: acr.properties.loginServer
      //   }
      // ]
    }
    template: {
      containers: [
        {
          name: '${appName}-app'
          image: appImage
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
