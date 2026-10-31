locals {
  public_access = length(var.allowed_ip_ranges) > 0
  premium       = var.sku == "Premium"
}

################################################################################
# Customer-managed key identity
################################################################################

resource "azurerm_user_assigned_identity" "cmk" {
  count = var.customer_managed_key != null ? 1 : 0

  name                = "id-${var.name}-cmk"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk" {
  count = var.customer_managed_key != null ? 1 : 0

  scope                            = var.customer_managed_key.key_vault_id
  role_definition_name             = "Key Vault Crypto Service Encryption User"
  principal_id                     = azurerm_user_assigned_identity.cmk[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# The registry validates key access at creation time, so wait for RBAC to propagate.
resource "time_sleep" "cmk_rbac" {
  count = var.customer_managed_key != null ? 1 : 0

  create_duration = "60s"

  triggers = {
    role_assignment = azurerm_role_assignment.cmk[0].id
  }
}

################################################################################
# Registry
################################################################################

resource "azurerm_container_registry" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  tags                = var.tags

  # Entra ID (RBAC) only: no admin user, no anonymous pulls.
  admin_enabled          = false
  anonymous_pull_enabled = false

  public_network_access_enabled = local.public_access
  network_rule_bypass_option    = "AzureServices"
  # Blocks copying images out of a private registry.
  export_policy_enabled = local.public_access || !local.premium

  zone_redundancy_enabled  = local.premium
  retention_policy_in_days = local.premium ? var.untagged_manifest_retention_days : null

  network_rule_set = local.premium && local.public_access ? [{
    default_action = "Deny"
    ip_rule        = [for cidr in var.allowed_ip_ranges : { action = "Allow", ip_range = cidr }]
  }] : []

  dynamic "georeplications" {
    for_each = var.georeplications
    content {
      location                        = georeplications.key
      zone_redundancy_enabled         = georeplications.value.zone_redundancy_enabled
      global_endpoint_routing_enabled = true
      tags                            = var.tags
    }
  }

  dynamic "identity" {
    for_each = var.customer_managed_key != null ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = [azurerm_user_assigned_identity.cmk[0].id]
    }
  }

  encryption = var.customer_managed_key != null ? [{
    key_vault_key_id   = var.customer_managed_key.key_vault_key_id
    identity_client_id = azurerm_user_assigned_identity.cmk[0].client_id
  }] : []

  lifecycle {
    precondition {
      condition     = local.premium || (var.private_endpoint == null && var.customer_managed_key == null && length(var.georeplications) == 0)
      error_message = "Private endpoints, customer-managed keys and geo-replication require the Premium SKU."
    }

    precondition {
      condition     = local.public_access || var.private_endpoint != null
      error_message = "With no allowed_ip_ranges the registry has no public access; configure private_endpoint so it is reachable."
    }
  }

  depends_on = [time_sleep.cmk_rbac]
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
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_endpoint.private_dns_zone_id]
  }
}

resource "azurerm_role_assignment" "this" {
  for_each = var.role_assignments

  scope                = azurerm_container_registry.this.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = each.value.principal_type
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_container_registry.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
