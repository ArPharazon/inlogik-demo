@minLength(5)
param appName string

param location string = resourceGroup().location

param acrSku string = 'Basic'
param keyVaultSkuName string = 'standard'

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
