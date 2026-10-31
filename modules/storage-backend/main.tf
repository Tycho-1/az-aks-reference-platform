resource "azurerm_storage_account" "this" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = var.account_replication_type
  access_tier              = "Hot"
  tags                     = var.tags

  # Entra ID only: no account keys or SAS, so access is governed by RBAC and auditable per identity.
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  local_user_enabled              = false
  sftp_enabled                    = false

  https_traffic_only_enabled        = true
  min_tls_version                   = "TLS1_2"
  allow_nested_items_to_be_public   = false
  cross_tenant_replication_enabled  = false
  infrastructure_encryption_enabled = true
  public_network_access             = var.network_access.public_network_access

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = var.blob_soft_delete_retention_days
    }

    container_delete_retention_policy {
      days = var.container_soft_delete_retention_days
    }
  }

  network_rules {
    default_action             = var.network_access.default_action
    bypass                     = ["AzureServices"]
    ip_rules                   = var.network_access.ip_rules
    virtual_network_subnet_ids = var.network_access.subnet_ids
  }
}

resource "azurerm_storage_container" "this" {
  for_each = toset(var.container_names)

  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

resource "azurerm_role_assignment" "state_contributors" {
  for_each = var.state_contributors

  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}

resource "azurerm_monitor_diagnostic_setting" "blob" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                       = "diag-${var.storage_account_name}-blob"
  target_resource_id         = "${azurerm_storage_account.this.id}/blobServices/default"
  log_analytics_workspace_id = var.log_analytics_workspace.id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_management_lock" "this" {
  count = var.delete_lock_enabled ? 1 : 0

  name       = "lock-${var.storage_account_name}"
  scope      = azurerm_storage_account.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects Terraform state from accidental deletion."
}
