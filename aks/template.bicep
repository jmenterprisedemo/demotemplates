param name string = 'jmaks'
param location string = resourceGroup().location
param aksAdminUserName string = 'azureuser'
param kubernetesVersion string = '1.22.6'
@secure()
param aksAdminPassword string

@allowed([
  'Free'
  'Standalone'
  'PerNode'
  'PerGB2018'
])
@description('Specifies the service tier of the workspace: Free, Standalone, PerNode, Per-GB.')
param logAnalyticsSku string = 'PerNode'

///
var readerRoleDefinitionName = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var contributorRoleDefinitionName = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
var acrPullRoleDefinitionName = '7f951dda-4ed3-4680-a7ca-43fe172d538d'
///

var uniqueName = substring('${name}${uniqueString(resourceGroup().id)}', 0, min(19, length(name) + 13))

var kv_name = '${uniqueName}kv'
var storageAccount_name = '${uniqueName}stg'
var registry_name = '${uniqueName}acr'
var vnet_name = '${uniqueName}vnet'
var vnet_default_nsg_name = '${uniqueName}vnnsg'
var pip_name = '${uniqueName}pip'
var log_analytics_workspace_name = '${uniqueName}logs'

var managedClusters_name = uniqueName
var nsg_name = '${uniqueName}nsg'
var userAssignedIdentity_name = '${uniqueName}mi'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2022-02-01-preview' = {
  name: registry_name
  location: location
  sku: {
    name: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    adminUserEnabled: true
    publicNetworkAccess: 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
  }
}

resource userAssignedIdentities_jmaksmi_name_resource 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: userAssignedIdentity_name
  location: location
}

resource vaults_jmaks_kv_name_resource 'Microsoft.KeyVault/vaults@2021-11-01-preview' = {
  name: kv_name
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enabledForDeployment: false
    publicNetworkAccess: 'Enabled'
    accessPolicies: [
      {
        tenantId: userAssignedIdentities_jmaksmi_name_resource.properties.tenantId
        objectId: userAssignedIdentities_jmaksmi_name_resource.properties.principalId
        permissions: {
          secrets: [
            'get'
            'list'
          ]
          certificates: [
            'get'
          ]
        }
      }
    ]
  }
}

resource networkSecurityGroups_jmaks_nsg_name_resource 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name: nsg_name
  location: location
  properties: {
    securityRules: []
  }
}

resource networkSecurityGroups_jmaks_vnet_default_nsg_northeurope_name_resource 'Microsoft.Network/networkSecurityGroups@2020-11-01' = {
  name: vnet_default_nsg_name
  location: location
  properties: {
    securityRules: [
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-11-01' = {
  name: vnet_name
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/8'
      ]
    }
    dhcpOptions: {
      dnsServers: []
    }
    // subnets must be declared here if we want that they do not fail when using
    // incremental deployment
    subnets: [ {
        name: 'default'
        properties: {
          addressPrefix: '10.240.0.0/16'
          networkSecurityGroup: {
            id: networkSecurityGroups_jmaks_vnet_default_nsg_northeurope_name_resource.id
          }
          serviceEndpoints: []
          delegations: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }

    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }

  resource default 'subnets' existing = {
    name: 'default'
  }
}

resource storageAccounts_jmaksstg_name_resource 'Microsoft.Storage/storageAccounts@2021-09-01' = {
  name: storageAccount_name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_0'
    allowBlobPublicAccess: true
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
    accessTier: 'Hot'
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2022-01-01' = {
  name: pip_name
  location: location
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: log_analytics_workspace_name
  location: location
  properties: {
    sku: {
      name: logAnalyticsSku
    }
    retentionInDays: 30
  }
}

resource managedClusters_jmaks_name_resource 'Microsoft.ContainerService/managedClusters@2022-05-02-preview' = {
  name: managedClusters_name
  location: location
  sku: {
    name: 'Basic'
    tier: 'Free'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: '${managedClusters_name}-dns'
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        vmSize: 'Standard_B4ms'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        kubeletDiskType: 'OS'
        vnetSubnetID: vnet::default.id
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        maxCount: 5
        minCount: 1
        enableAutoScaling: true
        powerState: {
          code: 'Running'
        }
        orchestratorVersion: kubernetesVersion
        enableNodePublicIP: false
        enableCustomCATrust: false
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        enableFIPS: false
      }
    ]
    windowsProfile: {
      adminUsername: aksAdminUserName
      adminPassword: aksAdminPassword
      enableCSIProxy: true
    }
    servicePrincipalProfile: {
      clientId: 'msi'
    }
    addonProfiles: {
      azurepolicy: {
        enabled: true
      }
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
        }
      }
    }
    enableRBAC: true
    networkProfile: {
      networkPlugin: 'azure'
      loadBalancerSku: 'Standard'
      outboundType: 'loadBalancer'
    }

    autoScalerProfile: {
      'balance-similar-node-groups': 'false'
      expander: 'random'
      'max-empty-bulk-delete': '10'
      'max-graceful-termination-sec': '600'
      'max-node-provision-time': '15m'
      'max-total-unready-percentage': '45'
      'new-pod-scale-up-delay': '0s'
      'ok-total-unready-count': '3'
      'scale-down-delay-after-add': '10m'
      'scale-down-delay-after-delete': '10s'
      'scale-down-delay-after-failure': '3m'
      'scale-down-unneeded-time': '10m'
      'scale-down-unready-time': '20m'
      'scale-down-utilization-threshold': '0.5'
      'scan-interval': '10s'
      'skip-nodes-with-local-storage': 'false'
      'skip-nodes-with-system-pods': 'true'
    }
    securityProfile: {
      defender: {
        logAnalyticsWorkspaceResourceId: logAnalyticsWorkspace.id
        securityMonitoring: {
          enabled: true
        }        
      }
    }
    storageProfile: {
      diskCSIDriver: {
        enabled: true
        version: 'v1'
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
    oidcIssuerProfile: {
      enabled: false
    }
  }
}

// ROLE ASSIGNMENTS

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry_name, acrPullRoleDefinitionName, resourceGroup().id)
  properties: {
    principalId: managedClusters_jmaks_name_resource.properties.identityProfile.kubeletIdentity.objectId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', acrPullRoleDefinitionName)
  }
}
