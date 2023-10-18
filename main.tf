// Variable Declaration
variable "subscription" {
  default = "ML-AMER-PlatformPOC"
}
# Resource Group variable
variable "rg" {
  default = "m1-rg-spring-poc-01"
}
# Input variable: Name of Storage container
variable "networking" {
  default = "sef-networking"
}

#-----------------------------------------------------
# Configure the Microsoft Azure provider
provider "azurerm" {
  features {}
}

# Create a Virtual Network
resource "azurerm_virtual_network" "tvnet" {
  name                = "vnet-sef"
  location            = "East US"
  resource_group_name = "m1-rg-spring-poc-01"
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_private_dns_zone" "dns_zone" {
  name                = "sef.medline.com"
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name

}

resource "azurerm_private_dns_zone_virtual_network_link" "link" {
  name                  = "vnet-link"
  resource_group_name   = azurerm_virtual_network.tvnet.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.dns_zone.name
  virtual_network_id    = azurerm_virtual_network.tvnet.id
  registration_enabled  = true
}

resource "azurerm_private_endpoint" "cosmos-endpoint" {
  name                = "audit-cosmosdb"
  location            = azurerm_virtual_network.tvnet.location
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  subnet_id           = azurerm_subnet.spring_apps.id

  private_service_connection {
    name                           = "example-privateserviceconnection"
    private_connection_resource_id = azurerm_cosmosdb_account.cosmosaccount.id
    subresource_names              = ["sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "sef-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.dns_zone.id]
  }
}

# Create a Subnet in the Virtual Network
resource "azurerm_subnet" "spring_core" {
  name                 = "sef-spring-core"
  resource_group_name  = azurerm_virtual_network.tvnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.tvnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Create a Subnet in the Virtual Network
resource "azurerm_subnet" "spring_apps" {
  name                 = "sef-spring-apps"
  resource_group_name  = azurerm_virtual_network.tvnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.tvnet.name
  address_prefixes     = ["10.0.3.0/24"]
}

# Create a Subnet in the Virtual Network
resource "azurerm_subnet" "sef_az_services" {
  name                 = "sef-services"
  resource_group_name  = azurerm_virtual_network.tvnet.resource_group_name
  virtual_network_name = azurerm_virtual_network.tvnet.name
  address_prefixes     = ["10.0.4.0/22"]
}



//AppInsights Configuration
resource "azurerm_application_insights" "sef-appinsights" {
  name                = "sef-app-ins"
  location            = azurerm_virtual_network.tvnet.location
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  application_type    = "web"
}







// Event Hub Configuration
resource "azurerm_eventhub_namespace" "sef-event-hub-namespace" {
  name                          = "sef-audit"
  location                      = azurerm_virtual_network.tvnet.location
  resource_group_name           = azurerm_virtual_network.tvnet.resource_group_name
  sku                           = "Standard"
  capacity                      = 1
  zone_redundant                = true
  public_network_access_enabled = false
  identity {
    type = "SystemAssigned"
  }
  tags = {
    environment = "Sef Event Hub for Audit"
  }
}

resource "azurerm_eventhub" "sef-eventhub" {
  name                = "audit"
  namespace_name      = azurerm_eventhub_namespace.sef-event-hub-namespace.name
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  partition_count     = 2
  message_retention   = 1
}


resource "azurerm_eventhub_consumer_group" "sef-eventhub-group" {
  name                = "audit-cg"
  namespace_name      = azurerm_eventhub_namespace.sef-event-hub-namespace.name
  eventhub_name       = azurerm_eventhub.sef-eventhub.name
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  user_metadata       = "test-meta-data"
}


resource "azurerm_cosmosdb_account" "cosmosaccount" {
  name                = "enterprise-audit"
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  location            = azurerm_virtual_network.tvnet.location
  offer_type          = "Standard"

  consistency_policy {
    consistency_level = "Strong"
  }
  geo_location {
    location          = azurerm_virtual_network.tvnet.location
    failover_priority = 0
    zone_redundant    = true
  }

  public_network_access_enabled = false

}
resource "azurerm_cosmosdb_sql_database" "cosmosdb" {
  name                = "audit"
  resource_group_name = azurerm_virtual_network.tvnet.resource_group_name
  account_name        = azurerm_cosmosdb_account.cosmosaccount.name
  throughput          = 400

}

resource "azurerm_cosmosdb_sql_container" "cosmos_container" {
  name                  = "ecom-audit"
  resource_group_name   = azurerm_virtual_network.tvnet.resource_group_name
  account_name          = azurerm_cosmosdb_account.cosmosaccount.name
  database_name         = azurerm_cosmosdb_sql_database.cosmosdb.name
  partition_key_path    = "/id"
  partition_key_version = 1
  throughput            = 400
}


resource "azurerm_spring_cloud_service" "azurespring" {
  name                     = "sef-ent-services"
  location                 = azurerm_virtual_network.tvnet.location
  resource_group_name      = azurerm_virtual_network.tvnet.resource_group_name
  sku_name                 = "E0"
  zone_redundant           = true
  build_agent_pool_size    = "S1"
  service_registry_enabled = true

  /* network {
    app_subnet_id             = azurerm_subnet.spring_apps.id
    cidr_ranges               = ["11.0.0.0/16","12.0.0.0/16","13.0.0.0/16"]
    service_runtime_subnet_id = azurerm_subnet.spring_core.id
  } */


}

resource "azurerm_spring_cloud_dev_tool_portal" "devtoolportal" {
  name                            = "default"
  spring_cloud_service_id         = azurerm_spring_cloud_service.azurespring.id
  public_network_access_enabled   = true
  application_accelerator_enabled = true
  application_live_view_enabled   = true
}

resource "azurerm_spring_cloud_configuration_service" "configservice" {
  name                    = "default"
  spring_cloud_service_id = azurerm_spring_cloud_service.azurespring.id
}

resource "azurerm_spring_cloud_application_insights_application_performance_monitoring" "appinsightsbinding" {
  name                         = "sefappinsights"
  spring_cloud_service_id      = azurerm_spring_cloud_service.azurespring.id
  connection_string            = azurerm_application_insights.sef-appinsights.instrumentation_key
  globally_enabled             = true
  role_name                    = "test-role"
  role_instance                = "test-instance"
  sampling_percentage          = 50
  sampling_requests_per_second = 10
}

resource "azurerm_spring_cloud_gateway" "springenterprisegateway" {
  name                    = "default"
  spring_cloud_service_id = azurerm_spring_cloud_service.azurespring.id

  https_only                    = true
  public_network_access_enabled = true
  instance_count                = 2

  api_metadata {
    description       = "example description"
    documentation_url = "https://www.example.com/docs"
    server_url        = "https://wwww.example.com"
    title             = "example title"
    version           = "1.0"
  }

  cors {
    credentials_allowed = false
    allowed_headers     = ["*"]
    allowed_methods     = ["PUT"]
    allowed_origins     = ["example.com"]
    exposed_headers     = ["x-example-header"]
    max_age_seconds     = 86400
  }

  quota {
    cpu    = "1"
    memory = "2Gi"
  }

}
