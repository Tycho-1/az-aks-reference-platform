################################################################################
# Container registry (private endpoint only)
################################################################################

module "acr" {
  source = "../../modules/container-registry"

  name                = "cr${var.workload}prod${var.location_short}${random_string.unique.result}"
  resource_group_name = azurerm_resource_group.this["aks"].name
  location            = var.location

  allowed_ip_ranges = var.acr_allowed_ip_ranges
  private_endpoint = {
    subnet_id           = module.spoke.subnet_ids["private_endpoints"]
    private_dns_zone_id = module.hub.private_dns_zone_ids["acr"]
  }

  customer_managed_key = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["acr"].versionless_id
  }

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
  tags                    = local.tags
}

################################################################################
# AKS: private API server, egress via firewall, CMK for disks and etcd
################################################################################

module "aks" {
  source = "../../modules/aks"

  name                = "aks-${local.suffix}"
  resource_group_name = azurerm_resource_group.this["aks"].name
  location            = var.location
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard"

  node_subnet_id = module.spoke.subnet_ids["aks_nodes"]
  network_profile = {
    outbound_type = "userDefinedRouting"
  }

  private_cluster = {
    enabled             = true
    private_dns_zone_id = module.hub.private_dns_zone_ids["aks"]
  }
  api_server_vnet_integration = {
    subnet_id = module.spoke.subnet_ids["aks_apiserver"]
  }

  control_plane_role_assignments = {
    route_table = {
      scope                = module.spoke.route_table_id
      role_definition_name = "Network Contributor"
    }
    private_dns_zone = {
      scope                = module.hub.private_dns_zone_ids["aks"]
      role_definition_name = "Private DNS Zone Contributor"
    }
  }

  admin_group_object_ids = var.aks_admin_group_object_ids
  acr_ids                = { platform = module.acr.id }

  disk_encryption = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["aks-disk"].versionless_id
  }
  kms = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["aks-kms"].id
    network_access   = "Private"
  }

  system_node_pool = {
    vm_size                 = var.system_node_pool_vm_size
    min_count               = var.system_node_pool_min_count
    os_disk_type            = var.system_node_pool_os_disk_type
    zones                   = var.node_availability_zones
    host_encryption_enabled = var.host_encryption_enabled
  }

  node_pools = {
    apps = {
      vm_size                 = var.apps_node_pool_vm_size
      os_disk_type            = var.apps_node_pool_os_disk_type
      zones                   = var.node_availability_zones
      priority                = var.apps_node_pool_priority
      min_count               = var.apps_node_pool_min_count
      max_count               = var.apps_node_pool_max_count
      host_encryption_enabled = var.host_encryption_enabled
      node_labels = {
        "workload-class" = "general"
      }
    }
  }

  log_analytics = {
    workspace_id     = azurerm_log_analytics_workspace.this.id
    defender_enabled = true
  }
  managed_prometheus = {
    monitor_workspace_id = azurerm_monitor_workspace.this.id
  }

  gitops = var.gitops_repository_url == null ? null : {
    repository_url = var.gitops_repository_url
    kustomizations = {
      infrastructure = {
        path = "./gitops/infrastructure/controllers"
      }
      apps = {
        path       = "./gitops/apps/production"
        depends_on = ["infrastructure"]
      }
    }
  }

  # Managed ingress in app-routing-system; matches gitops sample-api NetworkPolicy ingress rules.
  web_app_routing = {}

  tags = local.tags
}

################################################################################
# PostgreSQL: zone-redundant HA, geo-redundant backups, CMK in both regions
################################################################################

module "postgres" {
  count  = var.postgres_enabled ? 1 : 0
  source = "../../modules/postgresql-flexible-server"

  name                = "psql-${local.suffix}"
  resource_group_name = azurerm_resource_group.this["data"].name
  location            = var.location

  sku_name                     = "GP_Standard_D4ds_v5"
  geo_redundant_backup_enabled = true

  delegated_subnet_id = module.spoke.subnet_ids["postgres"]
  private_dns_zone = {
    id = module.hub.private_dns_zone_ids["postgres"]
  }

  entra_administrator = {
    object_id      = try(var.postgres_admin_group.object_id, "00000000-0000-0000-0000-000000000000")
    principal_name = try(var.postgres_admin_group.display_name, "unused")
    principal_type = "Group"
  }

  customer_managed_key = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["postgres"].versionless_id
    geo_backup = {
      location         = var.paired_location
      key_vault_id     = module.key_vault_paired[0].id
      key_vault_key_id = module.key_vault_paired[0].keys["postgres-geo-backup"].versionless_id
    }
  }

  databases  = { app = {} }
  extensions = ["PG_TRGM", "UUID-OSSP"]

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
  tags                    = local.tags
}
