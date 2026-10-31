resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = var.node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = each.value.vm_size
  vnet_subnet_id        = coalesce(each.value.vnet_subnet_id, var.node_subnet_id)
  zones                 = each.value.zones
  orchestrator_version  = var.kubernetes_version

  auto_scaling_enabled = each.value.auto_scaling_enabled
  node_count           = each.value.auto_scaling_enabled ? null : each.value.node_count
  min_count            = each.value.auto_scaling_enabled ? each.value.min_count : null
  max_count            = each.value.auto_scaling_enabled ? each.value.max_count : null
  max_pods             = each.value.max_pods

  os_type                 = "Linux"
  os_sku                  = each.value.os_sku
  os_disk_type            = each.value.os_disk_type
  os_disk_size_gb         = each.value.os_disk_size_gb
  host_encryption_enabled = each.value.host_encryption_enabled

  priority        = each.value.priority
  eviction_policy = each.value.priority == "Spot" ? "Delete" : null
  spot_max_price  = each.value.priority == "Spot" ? each.value.spot_max_price : null

  node_labels = each.value.node_labels
  # AKS adds this taint to Spot pools itself; declaring it avoids perpetual drift.
  node_taints = each.value.priority == "Spot" ? distinct(concat(each.value.node_taints, ["kubernetes.azure.com/scalesetpriority=spot:NoSchedule"])) : each.value.node_taints

  tags = merge(var.tags, each.value.tags)

  dynamic "upgrade_settings" {
    # Surge upgrades are not supported for Spot pools.
    for_each = each.value.priority == "Regular" ? [1] : []
    content {
      max_surge                = each.value.max_surge
      drain_timeout_in_minutes = each.value.drain_timeout_in_minutes
    }
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
