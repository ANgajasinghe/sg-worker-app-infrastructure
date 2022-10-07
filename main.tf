terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "~> 2.26"
    }
  }

  backend "azurerm" {
    resource_group_name  = "tamopstfstates"
    storage_account_name = "agtamopstf"
    container_name       = "tfstatedevops"
    key                  = "sg-terraform-status.tfstate"
  }
}

provider "azurerm" {

  features {}
}

resource "azurerm_resource_group" "resource_group" {
  name = "${var.project}-${var.environment}-rg"
  location = var.location
}

resource "azurerm_storage_account" "storage_account" {
  name = "${var.project}${var.environment}storage"
  resource_group_name = azurerm_resource_group.resource_group.name
  location = var.location
  account_tier = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "storage_container" {
  name = "function-releases"
  storage_account_name = "${azurerm_storage_account.storage_account.name}"
  container_access_type = "private"
}



# Create the azure cosmos db account
resource "azurerm_cosmosdb_account" "db" {
  name                = "${var.project}-${var.environment}-cosmosdb-mongo"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name
  offer_type          = "Standard"
  kind                = "MongoDB"

  enable_automatic_failover = true
  mongo_server_version= "4.0"

  capabilities {
    name = "EnableAggregationPipeline"
  }

  capabilities {
    name = "mongoEnableDocLevelTTL"
  }

  capabilities {
    name = "MongoDBv3.4"
  }

  capabilities {
    name = "EnableMongo"
  }

  consistency_policy {
    consistency_level  = "Eventual"
  }

  geo_location {
    location          = azurerm_resource_group.resource_group.location
    failover_priority = 0
  }
}

resource "azurerm_mysql_server" "mysql_server" {
  name                = "sg-mysqlserver"
  location            = azurerm_resource_group.resource_group.location
  resource_group_name = azurerm_resource_group.resource_group.name

  administrator_login = var.mysql-admin-login
  administrator_login_password = var.mysql-admin-password

  sku_name = var.mysql-sku-name
  version = var.mysql-version
  storage_mb = var.mysql-storage

  auto_grow_enabled                 = false
  geo_redundant_backup_enabled      = false
  infrastructure_encryption_enabled = false
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
}

resource "azurerm_mysql_database" "mysql_database" {
  name                = "sakila"
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysql_server.name
  charset             = "utf8"
  collation           = "utf8_unicode_ci"
  depends_on = [azurerm_mysql_server.mysql_server]
}

resource "azurerm_mysql_firewall_rule" "mysql-fw-rule" {
  name                = "globalaccess"
  resource_group_name = azurerm_resource_group.resource_group.name
  server_name         = azurerm_mysql_server.mysql_server.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "255.255.255.255"
  depends_on = [azurerm_mysql_server.mysql_server]
}



# Create azure function app 

resource "azurerm_application_insights" "application_insights" {
  name                = "${var.project}-${var.environment}-application-insights"
  location            = var.location
  resource_group_name = azurerm_resource_group.resource_group.name
  application_type    = "Node.JS"
}

resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "${var.project}-${var.environment}-app-service-plan"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = var.location
  kind                = "FunctionApp"
  reserved = true # this has to be set to true for Linux. Not related to the Premium Plan
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}

resource "azurerm_function_app" "function_app" {
  name                       = "${var.project}-${var.environment}-function-app"
  resource_group_name        = azurerm_resource_group.resource_group.name
  location                   = var.location
  app_service_plan_id        = azurerm_app_service_plan.app_service_plan.id
  app_settings = {
    AzureWebJobsStorage = azurerm_storage_account.storage_account.primary_connection_string
    "WEBSITE_RUN_FROM_PACKAGE"    = "1",
    "FUNCTIONS_WORKER_RUNTIME" = "dotnet",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.application_insights.instrumentation_key,
    "COSMOSDB_CONNECTION_STR" = azurerm_cosmosdb_account.db.connection_strings[0]
  }
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key
  version                    = "~3"

  depends_on = [azurerm_cosmosdb_account.db, azurerm_mysql_server.mysql_server, azurerm_application_insights.application_insights, azurerm_app_service_plan.app_service_plan]

  lifecycle {
    ignore_changes = [
      app_settings["WEBSITE_RUN_FROM_PACKAGE"],
    ]
  }
}