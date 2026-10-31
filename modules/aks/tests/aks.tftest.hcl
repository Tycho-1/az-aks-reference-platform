mock_provider "azurerm" {}

variables {
  name                   = "aks-test-dev-weu"
  resource_group_name    = "rg-test"
  location               = "westeurope"
  kubernetes_version     = "1.37"
  node_subnet_id         = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-aks"
  admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]

  api_server_authorized_ip_ranges = ["203.0.113.0/24"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = azurerm_kubernetes_cluster.this.local_account_disabled && azurerm_kubernetes_cluster.this.workload_identity_enabled && azurerm_kubernetes_cluster.this.oidc_issuer_enabled
    error_message = "Local accounts must be disabled and workload identity enabled by default."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.network_profile[0].network_plugin_mode == "overlay" && azurerm_kubernetes_cluster.this.network_profile[0].network_data_plane == "cilium"
    error_message = "Cluster must use Azure CNI Overlay with the Cilium data plane."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.default_node_pool[0].only_critical_addons_enabled && length(azurerm_kubernetes_cluster.this.default_node_pool[0].zones) == 3
    error_message = "System pool must be tainted for critical add-ons and spread across three zones."
  }

  assert {
    condition     = azurerm_kubernetes_cluster.this.sku_tier == "Standard" && azurerm_kubernetes_cluster.this.automatic_upgrade_channel == "patch"
    error_message = "Standard tier and patch auto-upgrade are expected defaults."
  }

  assert {
    condition     = azurerm_role_assignment.control_plane_network.scope == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test"
    error_message = "Network Contributor must be scoped to the VNet derived from the node subnet."
  }
}

run "spot_pool_gets_taint_and_no_surge" {
  command = plan

  variables {
    node_pools = {
      spot = {
        vm_size  = "Standard_D4ds_v5"
        priority = "Spot"
      }
    }
  }

  assert {
    condition     = contains(azurerm_kubernetes_cluster_node_pool.this["spot"].node_taints, "kubernetes.azure.com/scalesetpriority=spot:NoSchedule")
    error_message = "Spot pools must declare the AKS spot taint."
  }

  assert {
    condition     = length(azurerm_kubernetes_cluster_node_pool.this["spot"].upgrade_settings) == 0
    error_message = "Spot pools must not configure surge upgrades."
  }
}

run "requires_admin_group_without_local_accounts" {
  command = plan

  variables {
    admin_group_object_ids = []
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}

run "rejects_patch_version_pin" {
  command = plan

  variables {
    kubernetes_version = "1.33.2"
  }

  expect_failures = [var.kubernetes_version]
}

run "rejects_authorized_ips_on_private_cluster" {
  command = plan

  variables {
    private_cluster = { enabled = true }
  }

  expect_failures = [azurerm_kubernetes_cluster.this]
}
