locals {
  virtual_network_id = regex("^(.+)/subnets/[^/]+$", var.node_subnet_id)[0]
}

################################################################################
# Identities
#
# User-assigned identities let RBAC be granted before the cluster exists, avoiding
# the race where a system-assigned identity has no permissions during creation.
################################################################################

resource "azurerm_user_assigned_identity" "control_plane" {
  name                = "id-${var.name}-control-plane"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "id-${var.name}-kubelet"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "control_plane_network" {
  scope                            = local.virtual_network_id
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "control_plane_kubelet_operator" {
  scope                            = azurerm_user_assigned_identity.kubelet.id
  role_definition_name             = "Managed Identity Operator"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "control_plane_additional" {
  for_each = var.control_plane_role_assignments

  scope                            = each.value.scope
  role_definition_name             = each.value.role_definition_name
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# AKS validates its identity's permissions during creation; give RBAC time to propagate.
resource "time_sleep" "control_plane_rbac" {
  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.control_plane_network,
    azurerm_role_assignment.control_plane_kubelet_operator,
    azurerm_role_assignment.control_plane_additional,
    azurerm_role_assignment.control_plane_disk_encryption_set,
    azurerm_role_assignment.control_plane_kms_crypto,
    azurerm_role_assignment.control_plane_kms_private_link,
  ]
}

resource "azurerm_role_assignment" "kubelet_acr_pull" {
  for_each = var.acr_ids

  scope                            = each.value
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

################################################################################
# Cluster
################################################################################

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = coalesce(var.dns_prefix, var.name)
  node_resource_group = var.node_resource_group_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  private_cluster_enabled             = var.private_cluster.enabled
  private_dns_zone_id                 = var.private_cluster.enabled ? var.private_cluster.private_dns_zone_id : null
  private_cluster_public_fqdn_enabled = var.private_cluster.enabled ? var.private_cluster.public_fqdn_enabled : null

  local_account_disabled            = var.local_account_disabled
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = var.azure_policy_enabled
  image_cleaner_enabled             = var.image_cleaner_interval_hours != null
  image_cleaner_interval_hours      = var.image_cleaner_interval_hours
  cost_analysis_enabled             = var.cost_analysis_enabled && var.sku_tier != "Free"
  disk_encryption_set_id            = try(azurerm_disk_encryption_set.this[0].id, null)

  default_node_pool {
    name                         = var.system_node_pool.name
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = var.node_subnet_id
    zones                        = var.system_node_pool.zones
    type                         = "VirtualMachineScaleSets"
    only_critical_addons_enabled = true
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    max_pods                     = var.system_node_pool.max_pods
    os_sku                       = var.system_node_pool.os_sku
    os_disk_type                 = var.system_node_pool.os_disk_type
    os_disk_size_gb              = var.system_node_pool.os_disk_size_gb
    host_encryption_enabled      = var.system_node_pool.host_encryption_enabled
    orchestrator_version         = var.kubernetes_version
    temporary_name_for_rotation  = var.system_node_pool.temporary_name_for_rotation
    tags                         = var.tags

    upgrade_settings {
      max_surge                = var.system_node_pool.max_surge
      drain_timeout_in_minutes = var.system_node_pool.drain_timeout_in_minutes
    }
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    pod_cidr            = var.network_profile.pod_cidr
    service_cidr        = var.network_profile.service_cidr
    dns_service_ip      = var.network_profile.dns_service_ip
    outbound_type       = var.network_profile.outbound_type
  }

  dynamic "api_server_access_profile" {
    for_each = length(var.api_server_authorized_ip_ranges) > 0 || var.api_server_vnet_integration != null ? [1] : []
    content {
      authorized_ip_ranges                = length(var.api_server_authorized_ip_ranges) > 0 ? var.api_server_authorized_ip_ranges : null
      virtual_network_integration_enabled = var.api_server_vnet_integration != null
      subnet_id                           = try(var.api_server_vnet_integration.subnet_id, null)
    }
  }

  maintenance_window_auto_upgrade {
    frequency   = var.maintenance_window_auto_upgrade.frequency
    interval    = var.maintenance_window_auto_upgrade.interval
    duration    = var.maintenance_window_auto_upgrade.duration
    day_of_week = var.maintenance_window_auto_upgrade.day_of_week
    start_time  = var.maintenance_window_auto_upgrade.start_time
    utc_offset  = var.maintenance_window_auto_upgrade.utc_offset
  }

  maintenance_window_node_os {
    frequency   = var.maintenance_window_node_os.frequency
    interval    = var.maintenance_window_node_os.interval
    duration    = var.maintenance_window_node_os.duration
    day_of_week = var.maintenance_window_node_os.day_of_week
    start_time  = var.maintenance_window_node_os.start_time
    utc_offset  = var.maintenance_window_node_os.utc_offset
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.key_vault_secrets_provider.enabled ? [1] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = var.key_vault_secrets_provider.secret_rotation_interval
    }
  }

  dynamic "key_management_service" {
    for_each = var.kms != null ? [var.kms] : []
    content {
      key_vault_key_id         = key_management_service.value.key_vault_key_id
      key_vault_network_access = key_management_service.value.network_access
    }
  }

  dynamic "oms_agent" {
    for_each = try(var.log_analytics.container_insights_enabled, false) ? [1] : []
    content {
      log_analytics_workspace_id      = var.log_analytics.workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  dynamic "microsoft_defender" {
    for_each = try(var.log_analytics.defender_enabled, false) ? [1] : []
    content {
      log_analytics_workspace_id = var.log_analytics.workspace_id
    }
  }

  dynamic "monitor_metrics" {
    for_each = var.managed_prometheus != null ? [1] : []
    content {}
  }

  dynamic "web_app_routing" {
    for_each = var.web_app_routing != null ? [var.web_app_routing] : []
    content {
      dns_zone_ids = web_app_routing.value.dns_zone_ids
    }
  }

  dynamic "workload_autoscaler_profile" {
    for_each = var.workload_autoscaler.keda_enabled || var.workload_autoscaler.vertical_pod_autoscaler_enabled ? [1] : []
    content {
      keda_enabled                    = var.workload_autoscaler.keda_enabled
      vertical_pod_autoscaler_enabled = var.workload_autoscaler.vertical_pod_autoscaler_enabled
    }
  }

  lifecycle {
    # The cluster autoscaler owns the node count.
    ignore_changes = [default_node_pool[0].node_count]

    precondition {
      condition     = !var.local_account_disabled || length(var.admin_group_object_ids) > 0
      error_message = "admin_group_object_ids must contain at least one group when local accounts are disabled, otherwise nobody can administer the cluster."
    }

    precondition {
      condition     = !(var.private_cluster.enabled && length(var.api_server_authorized_ip_ranges) > 0)
      error_message = "api_server_authorized_ip_ranges cannot be combined with a private cluster."
    }

    precondition {
      condition     = (var.kms == null ? true : var.kms.network_access != "Private") || var.api_server_vnet_integration != null
      error_message = "KMS with a private key vault requires api_server_vnet_integration."
    }
  }

  depends_on = [time_sleep.control_plane_rbac]
}

check "public_api_server_is_restricted" {
  assert {
    condition     = var.private_cluster.enabled || length(var.api_server_authorized_ip_ranges) > 0
    error_message = "The API server is public and reachable from any IP. Set api_server_authorized_ip_ranges or enable private_cluster for production."
  }
}
