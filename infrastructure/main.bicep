@description('The AAD object id of a user that should be granted access to Key Vault contents')
param keyVaultAccessPolicyTargetObjectId string

@description('The name of the Azure ML Workspace to create or update')
param mlWorkspaceName string

@description('The name of the Azure Key Vault to create or update')
param keyVaultName string

@description('The name of the Storage Account used by the Azure ML Workspace')
param storageAccountName string

@description('The name of the Azure ML Compute Instance to create or update')
param computeInstanceName string

@description('The name of the Azure ML Cluster to create or update')
param mlClusterName string

@description('The name of the Application Insights resource to create or update')
param appInsightsName string

@description('The name of the Azure Container Registry to create or update')
param containerRegistryName string

@description('The name of the Data Factory resource to create or update')
param dataFactoryName string

@description('The SKU for the Azure ML compute instance')
param computeInstanceSku string

@description('The SKU for the Azure ML cluster')
param mlClusterSku string

@description('The maximum number of compute nodes for the ML cluster')
param mlClusterMaxNodeCount int

@description('The minimum number of compute nodes for the ML cluster')
param mlClusterMinNodeCount int

@description('The AAD object id of the user assigned to the ML compute instance')
param mlComputeAssignedUser string

var location = resourceGroup().location
var tenantId = subscription().tenantId

resource vault 'Microsoft.KeyVault/vaults@2020-04-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enabledForDeployment: false
    enableSoftDelete: true
    accessPolicies: [
      {
        tenantId: tenantId
        objectId: keyVaultAccessPolicyTargetObjectId
        permissions: {
          keys: [
            'get'
            'list'
            'update'
            'create'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          secrets: [
            'get'
            'list'
            'set'
            'delete'
            'recover'
            'backup'
            'restore'
          ]
          certificates: [
            'get'
            'list'
            'update'
            'create'
            'import'
            'delete'
            'recover'
            'backup'
            'restore'
            'managecontacts'
            'manageissuers'
            'getissuers'
            'listissuers'
            'setissuers'
            'deleteissuers'
          ]
        }
      }
    ]
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2020-08-01-preview' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

resource storageCors 'Microsoft.Storage/storageAccounts/blobServices@2020-08-01-preview' = {
  name: '${storage.name}/default'
  properties: {
    cors: {
      corsRules: [
        {
          maxAgeInSeconds: 1800
          allowedOrigins: [
            'https://mlworkspace.azure.ai'
            'https://ml.azure.com'
            'https://*.ml.azure.com'
            'https://mlworkspace.azureml-test.net'
          ]
          allowedMethods: [
            'GET'
            'HEAD'
          ]
          exposedHeaders: [
            '*'
          ]
          allowedHeaders: [
            '*'
          ]          
        }
      ]
    }
  }
}

resource mlMetricsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storage.name}/default/azureml-metrics'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  } 
}

resource mlRevisionsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storage.name}/default/revisions'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  } 
}

resource mlSnapshotsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storage.name}/default/snapshots'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  } 
}

resource mlSnapshotZipsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2019-06-01' = {
  name: '${storage.name}/default/snapshotzips'
  properties: {
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  } 
}

// TODO:  Need containers and shares that have GUID in share/container name, not sure how those map
// to aml ws

resource appInsights 'Microsoft.Insights/components@2020-02-02-preview' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'ApplicationInsights'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2020-11-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
     adminUserEnabled: true
     policies: {
       quarantinePolicy: {
         status: 'disabled'
       }
       trustPolicy: {
         type: 'Notary'
         status: 'disabled'
       }
       retentionPolicy: {
         days: 7
         status: 'disabled'
       }
     }
     encryption: {
       status: 'disabled'
     }
     dataEndpointEnabled: false
     publicNetworkAccess: 'Enabled'
     networkRuleBypassOptions: 'AzureServices'
     zoneRedundancy: 'Disabled'
  }
}

resource mlWorkspace 'Microsoft.MachineLearningServices/workspaces@2020-06-01' = {
  name: mlWorkspaceName
  location: location
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: mlWorkspaceName
    storageAccount: storage.id
    containerRegistry: containerRegistry.id
    keyVault: vault.id
    applicationInsights: appInsights.id
    hbiWorkspace: false
    allowPublicAccessWhenBehindVnet: false
    discoveryUrl: 'https://${location}.experiments.azureml.net/discovery'
  }
}

resource mlCompute 'Microsoft.MachineLearningServices/workspaces/computes@2021-01-01' = {
  name: '${mlWorkspace.name}/${computeInstanceName}'
  location: location
  properties: {
    computeType: 'ComputeInstance'
    computeLocation: location
    properties: {
      vmSize: computeInstanceSku
      sshSettings: {
        sshPublicAccess: 'Disabled'        
      }
      applicationSharingPolicy: 'Shared'
      personalComputeInstanceSettings: {
        assignedUser: {
          objectId: mlComputeAssignedUser
          tenantId: tenantId
        }
      }
      schedules: [
        {
          type: 'RecurrenceStop'
          recurrence: {
            frequency: 'Day'
            interval: 1
            timeZone: 'Central Daylight Time'
            schedule: {
              hours: [18]
              minutes: [00]
            }
            startTime: '2021-01-01T00:00:00'
          }
        }
      ]
    }
  }
}

resource mlCluster 'Microsoft.MachineLearningServices/workspaces/computes@2021-01-01' = {
  name: '${mlWorkspace.name}/${mlClusterName}'
  location: location
  identity: {
    type: 'None'
  }
  properties: {
    computeType: 'AmlCompute'
    computeLocation: location
    properties: {
      vmSize: mlClusterSku
      vmPriority: 'Dedicated'
      scaleSettings: {
        maxNodeCount: mlClusterMaxNodeCount
        minNodeCount: mlClusterMinNodeCount
        nodeIdleTimeBeforeScaleDown: 'PT2M'
      }
      remoteLoginPortPublicAccess: 'Enabled'
      osType: 'Linux'
      isolatedNetwork: false
    }
  }
}

resource dataFactory 'Microsoft.DataFactory/factories@2018-06-01' = {
  name: dataFactoryName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}
