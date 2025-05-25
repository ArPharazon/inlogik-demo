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

// Role assignment: 'Key Vault Secrets Officer' for adding secrets to Key Vault
// see: https://learn.microsoft.com/en-us/azure/key-vault/general/rbac-guide?tabs=azure-cli
resource acrKeyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, acr.id, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') 
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: acr.identity.principalId
    principalType: 'ServicePrincipal'
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

// Managed Environment for Container Apps
resource managedEnv 'Microsoft.App/managedEnvironments@2025-01-01' = {
  name: '${appName}-env'
  location: location
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
      registries: [
        {
          server: acr.properties.loginServer
        }
      ]
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
