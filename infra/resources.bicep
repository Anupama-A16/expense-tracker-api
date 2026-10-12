targetScope = 'resourceGroup'

@description('Azure region for the resources.')
param location string

@description('Common prefix generated from workload name and environment.')
param namePrefix string

@description('MySQL administrator username.')
param mysqlAdminUsername string

@description('MySQL administrator password.')
@secure()
param mysqlAdminPassword string

@description('Name of the MySQL database.')
param mysqlDatabaseName string

@description('Tags applied to resources.')
param tags object

// --------------------------------------------------
// Resource Names
// --------------------------------------------------

var appServicePlanName = '${namePrefix}-plan'

var webAppName = '${namePrefix}-web-${uniqueString(resourceGroup().id)}'

var mysqlServerName = '${namePrefix}-mysql-${uniqueString(resourceGroup().id)}'

// --------------------------------------------------
// App Service Plan
// --------------------------------------------------

resource appServicePlan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: appServicePlanName
  location: location
  tags: tags

  sku: {
    name: 'B1'
    tier: 'Basic'
  }

  kind: 'linux'

  properties: {
    reserved: true
  }
}

// --------------------------------------------------
// MySQL Flexible Server
// --------------------------------------------------

resource mysqlServer 'Microsoft.DBforMySQL/flexibleServers@2024-12-30' = {
  name: mysqlServerName
  location: location
  tags: tags

  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }

  properties: {
    administratorLogin: mysqlAdminUsername
    administratorLoginPassword: mysqlAdminPassword

    version: '8.4'

    storage: {
      storageSizeGB: 20
      autoGrow: 'Disabled'
    }

    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }

    highAvailability: {
      mode: 'Disabled'
    }
  }
}

// --------------------------------------------------
// MySQL Firewall Rule
// Allows Azure services to connect to MySQL
// --------------------------------------------------

resource mysqlFirewallRule 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2024-12-30' = {
  parent: mysqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// --------------------------------------------------
// MySQL Database
// --------------------------------------------------

resource mysqlDatabase 'Microsoft.DBforMySQL/flexibleServers/databases@2024-12-30' = {
  parent: mysqlServer
  name: mysqlDatabaseName

  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_unicode_ci'
  }
}

// --------------------------------------------------
// Azure App Service
// --------------------------------------------------

resource webApp 'Microsoft.Web/sites@2025-03-01' = {
  name: webAppName
  location: location
  tags: tags

  kind: 'app,linux'

  properties: {
    serverFarmId: appServicePlan.id

    httpsOnly: true

    siteConfig: {
      linuxFxVersion: 'PYTHON|3.12'

      alwaysOn: false

      appCommandLine: 'gunicorn --bind=0.0.0.0 --timeout 600 app.main:app'

      appSettings: [
        {
          name: 'MYSQL_HOST'
          value: mysqlServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'MYSQL_USER'
          value: mysqlAdminUsername
        }
        {
          name: 'MYSQL_PASSWORD'
          value: mysqlAdminPassword
        }
        {
          name: 'MYSQL_DATABASE'
          value: mysqlDatabaseName
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }

  dependsOn: [
    mysqlDatabase
  ]
}

// --------------------------------------------------
// Outputs
// --------------------------------------------------

output appServicePlanName string = appServicePlan.name

output webAppName string = webApp.name

output webAppUrl string = 'https://${webApp.properties.defaultHostName}'

output mysqlServerName string = mysqlServer.name

output mysqlDatabaseName string = mysqlDatabase.name
