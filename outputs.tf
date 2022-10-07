output "function_app_name" {
  value = azurerm_function_app.function_app.name
  description = "Deployed function app name"
}

output "function_app_default_hostname" {
  value = azurerm_function_app.function_app.default_hostname
  description = "Deployed function app hostname"
}


output "cosmosdb_connection_string" {
  value = azurerm_cosmosdb_account.db.connection_strings[0]
  sensitive = true
  description = "Deployed function app hostname"
}

output "mysql_server" {
  value = azurerm_mysql_server.mysql_server
  description = "Deployed sqlserver name"
  sensitive = true
}