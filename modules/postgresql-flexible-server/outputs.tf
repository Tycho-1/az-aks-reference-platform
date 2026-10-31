output "id" {
  description = "Resource ID of the server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "name" {
  description = "Name of the server."
  value       = azurerm_postgresql_flexible_server.this.name
}

output "fqdn" {
  description = "Private FQDN of the server."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "private_dns_zone_id" {
  description = "ID of the private DNS zone used by the server."
  value       = local.private_dns_zone_id
}

output "database_names" {
  description = "Names of the databases created by the module."
  value       = keys(azurerm_postgresql_flexible_server_database.this)
}

output "connection_string_template" {
  description = "libpq connection string without credentials. With Entra auth, the password is an access token for https://ossrdbms-aad.database.windows.net."
  value       = "host=${azurerm_postgresql_flexible_server.this.fqdn} port=5432 dbname=<database> user=<entra-principal-name> sslmode=require"
}
