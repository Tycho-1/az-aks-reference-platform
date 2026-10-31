data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name
  tags                = var.tags

  rbac_authorization_enabled = true
  purge_protection_enabled   = true
  soft_delete_retention_days = var.soft_delete_retention_days

  public_network_access_enabled = length(var.allowed_ip_ranges) > 0

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.allowed_ip_ranges
  }
}

resource "azurerm_private_endpoint" "this" {
  count = var.private_endpoint != null ? 1 : 0

  name                = "pe-${var.name}"
  location            = coalesce(var.private_endpoint.location, var.location)
  resource_group_name = var.resource_group_name
  subnet_id           = var.private_endpoint.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${var.name}"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_endpoint.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "deployer" {
  count = var.deployer_crypto_officer_enabled ? 1 : 0

  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = azurerm_key_vault.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}

# Data plane RBAC takes a while to propagate; creating keys immediately after the grant fails.
resource "time_sleep" "rbac_propagation" {
  create_duration = "60s"

  triggers = {
    deployer = try(azurerm_role_assignment.deployer[0].id, "")
  }
}

resource "azurerm_key_vault_key" "this" {
  for_each = var.keys

  name         = each.key
  key_vault_id = azurerm_key_vault.this.id
  key_type     = each.value.key_type
  key_size     = each.value.key_size
  key_opts     = each.value.key_opts
  tags         = var.tags

  rotation_policy {
    automatic {
      time_after_creation = each.value.rotate_after
    }
  }

  depends_on = [
    time_sleep.rbac_propagation,
    azurerm_private_endpoint.this,
  ]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_key_vault.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
