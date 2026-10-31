data "azurerm_client_config" "current" {}

locals {
  # Decided on the presence of inputs (known at plan time), never on possibly-unknown IDs.
  create_private_dns_zone = var.private_dns_zone.virtual_network_ids != null
  private_dns_zone_id     = local.create_private_dns_zone ? azurerm_private_dns_zone.this[0].id : var.private_dns_zone.id

  cmk_enabled      = var.customer_managed_key != null
  cmk_geo_enabled  = var.customer_managed_key == null ? false : var.customer_managed_key.geo_backup != null
  cmk_identity_ids = concat(azurerm_user_assigned_identity.cmk[*].id, azurerm_user_assigned_identity.cmk_geo[*].id)
}

################################################################################
# Customer-managed key identities
################################################################################

resource "azurerm_user_assigned_identity" "cmk" {
  count = local.cmk_enabled ? 1 : 0

  name                = "id-${var.name}-cmk"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk" {
  count = local.cmk_enabled ? 1 : 0

  scope                            = var.customer_managed_key.key_vault_id
  role_definition_name             = "Key Vault Crypto Service Encryption User"
  principal_id                     = azurerm_user_assigned_identity.cmk[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_user_assigned_identity" "cmk_geo" {
  count = local.cmk_geo_enabled ? 1 : 0

  name                = "id-${var.name}-cmk-geo"
  location            = var.customer_managed_key.geo_backup.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "cmk_geo" {
  count = local.cmk_geo_enabled ? 1 : 0

  scope                            = var.customer_managed_key.geo_backup.key_vault_id
  role_definition_name             = "Key Vault Crypto Service Encryption User"
  principal_id                     = azurerm_user_assigned_identity.cmk_geo[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "cmk_rbac" {
  count = local.cmk_enabled ? 1 : 0

  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.cmk,
    azurerm_role_assignment.cmk_geo,
  ]
}

resource "azurerm_private_dns_zone" "this" {
  count = local.create_private_dns_zone ? 1 : 0

  name                = "${var.name}.private.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.create_private_dns_zone ? var.private_dns_zone.virtual_network_ids : tomap({})

  name                = "link-${each.key}"
  private_dns_zone_id = azurerm_private_dns_zone.this[0].id
  virtual_network_id  = each.value
  tags                = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  version             = var.postgresql_version
  sku_name            = var.sku_name
  zone                = var.zone
  tags                = var.tags

  storage_mb        = var.storage_mb
  auto_grow_enabled = var.auto_grow_enabled

  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = var.geo_redundant_backup_enabled

  delegated_subnet_id           = var.delegated_subnet_id
  private_dns_zone_id           = local.private_dns_zone_id
  public_network_access_enabled = false

  administrator_login               = var.password_auth_enabled ? var.administrator_login : null
  administrator_password_wo         = var.password_auth_enabled ? var.administrator_password : null
  administrator_password_wo_version = var.password_auth_enabled ? var.administrator_password_version : null

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = var.password_auth_enabled
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }

  dynamic "high_availability" {
    for_each = var.high_availability != null ? [var.high_availability] : []
    content {
      mode                      = high_availability.value.mode
      standby_availability_zone = high_availability.value.mode == "ZoneRedundant" ? high_availability.value.standby_availability_zone : null
    }
  }

  dynamic "identity" {
    for_each = local.cmk_enabled ? [1] : []
    content {
      type         = "UserAssigned"
      identity_ids = local.cmk_identity_ids
    }
  }

  dynamic "customer_managed_key" {
    for_each = local.cmk_enabled ? [var.customer_managed_key] : []
    content {
      key_vault_key_id                     = customer_managed_key.value.key_vault_key_id
      primary_user_assigned_identity_id    = azurerm_user_assigned_identity.cmk[0].id
      geo_backup_key_vault_key_id          = try(customer_managed_key.value.geo_backup.key_vault_key_id, null)
      geo_backup_user_assigned_identity_id = try(azurerm_user_assigned_identity.cmk_geo[0].id, null)
    }
  }

  maintenance_window {
    day_of_week  = var.maintenance_window.day_of_week
    start_hour   = var.maintenance_window.start_hour
    start_minute = var.maintenance_window.start_minute
  }

  lifecycle {
    # After a failover Azure swaps primary and standby zones; don't fight it.
    ignore_changes = [zone, high_availability[0].standby_availability_zone]

    precondition {
      condition     = !var.password_auth_enabled || var.administrator_login != null
      error_message = "administrator_login is required when password_auth_enabled = true."
    }

    precondition {
      condition     = var.high_availability == null || !startswith(var.sku_name, "B_")
      error_message = "High availability is not supported on Burstable (B_) SKUs. Use GP_ or MO_, or set high_availability = null."
    }

    precondition {
      condition     = !(local.cmk_enabled && var.geo_redundant_backup_enabled) || local.cmk_geo_enabled
      error_message = "Geo-redundant backups with a customer-managed key need customer_managed_key.geo_backup (a key in the paired region)."
    }
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this,
    time_sleep.cmk_rbac,
  ]
}

resource "azurerm_postgresql_flexible_server_active_directory_administrator" "this" {
  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = var.entra_administrator.object_id
  principal_name      = var.entra_administrator.principal_name
  principal_type      = var.entra_administrator.principal_type
}

resource "azurerm_postgresql_flexible_server_database" "this" {
  for_each = var.databases

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = each.value.charset
  collation = each.value.collation
}

resource "azurerm_postgresql_flexible_server_configuration" "extensions" {
  count = length(var.extensions) > 0 ? 1 : 0

  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = join(",", var.extensions)
}

resource "azurerm_postgresql_flexible_server_configuration" "this" {
  for_each = var.server_parameters

  name      = each.key
  server_id = azurerm_postgresql_flexible_server.this.id
  value     = each.value

  depends_on = [azurerm_postgresql_flexible_server_configuration.extensions]
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                       = "diag-${var.name}"
  target_resource_id         = azurerm_postgresql_flexible_server.this.id
  log_analytics_workspace_id = var.log_analytics_workspace.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_management_lock" "this" {
  count = var.delete_lock_enabled ? 1 : 0

  name       = "lock-${var.name}"
  scope      = azurerm_postgresql_flexible_server.this.id
  lock_level = "CanNotDelete"
  notes      = "Protects the database server from accidental deletion."
}
