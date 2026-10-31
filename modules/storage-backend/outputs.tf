output "storage_account_id" {
  description = "ID of the storage account."
  value       = azurerm_storage_account.this.id
}

output "storage_account_name" {
  description = "Name of the storage account."
  value       = azurerm_storage_account.this.name
}

output "containers" {
  description = "Created containers keyed by name."
  value = {
    for name, c in azurerm_storage_container.this : name => {
      id  = c.id
      url = c.url
    }
  }
}

output "backend_configs" {
  description = "Ready-to-use azurerm backend settings per container. Set `key` per stack, e.g. \"platform/aks.tfstate\"."
  value = {
    for name in var.container_names : name => {
      resource_group_name  = var.resource_group_name
      storage_account_name = azurerm_storage_account.this.name
      container_name       = name
      use_azuread_auth     = true
    }
  }
}
