################################################################################
# Customer-managed keys
#
# One vault per region holds the platform encryption keys. Consumers use versionless
# key IDs (automatic rotation) except AKS KMS, which requires a versioned key.
################################################################################

module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-${var.workload}-${var.location_short}-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.this["security"].name
  location            = var.location

  allowed_ip_ranges = var.operator_ip_ranges
  private_endpoint = {
    subnet_id           = module.spoke.subnet_ids["private_endpoints"]
    private_dns_zone_id = module.hub.private_dns_zone_ids["key_vault"]
  }

  keys = merge(
    {
      aks-disk = {}
      aks-kms = {
        key_opts = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]
      }
      acr = {}
    },
    var.postgres_enabled ? { postgres = {} } : {},
  )

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
  tags                    = local.tags
}

module "key_vault_paired" {
  count  = var.postgres_enabled ? 1 : 0
  source = "../../modules/key-vault"

  name                = "kv-${var.workload}-geo-${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.this["security"].name
  location            = var.paired_location

  allowed_ip_ranges = var.operator_ip_ranges
  private_endpoint = {
    location            = var.location
    subnet_id           = module.spoke.subnet_ids["private_endpoints"]
    private_dns_zone_id = module.hub.private_dns_zone_ids["key_vault"]
  }

  keys = {
    postgres-geo-backup = {}
  }

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
  tags                    = local.tags
}
