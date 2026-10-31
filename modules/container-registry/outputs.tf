output "id" {
  description = "ID of the registry. Pass to the AKS module's `acr_ids` to grant AcrPull to the kubelet."
  value       = azurerm_container_registry.this.id
}

output "name" {
  description = "Name of the registry."
  value       = azurerm_container_registry.this.name
}

output "login_server" {
  description = "Login server, e.g. crplatformprod.azurecr.io."
  value       = azurerm_container_registry.this.login_server
}
