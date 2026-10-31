output "id" {
  description = "ID of the Key Vault."
  value       = azurerm_key_vault.this.id
}

output "name" {
  description = "Name of the Key Vault."
  value       = azurerm_key_vault.this.name
}

output "vault_uri" {
  description = "Data plane URI of the Key Vault."
  value       = azurerm_key_vault.this.vault_uri
}

output "keys" {
  description = <<-EOT
    Keys keyed by name. Use `versionless_id` for services that follow rotation automatically
    (disk encryption sets, ACR, PostgreSQL) and `id` (versioned) for AKS KMS.
  EOT
  value = {
    for k, key in azurerm_key_vault_key.this : k => {
      id             = key.id
      versionless_id = key.versionless_id
    }
  }
}
