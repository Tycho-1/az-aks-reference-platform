locals {
  suffix = "${var.workload}-prod-${var.location_short}"

  spoke_subnets = {
    aks_nodes         = cidrsubnet(var.spoke_address_space, 6, 0)
    aks_apiserver     = cidrsubnet(var.spoke_address_space, 12, 64)
    postgres          = cidrsubnet(var.spoke_address_space, 8, 8)
    private_endpoints = cidrsubnet(var.spoke_address_space, 8, 9)
  }

  # Egress Flux and the GitOps content need through the firewall: the Git host and the
  # cert-manager chart and images. Workload images come from the private ACR instead.
  gitops_egress_fqdns = var.gitops_repository_url == null ? [] : [
    regex("^https://([^/]+)/", var.gitops_repository_url)[0],
    "charts.jetstack.io",
    "quay.io",
    "*.quay.io",
  ]

  tags = {
    workload    = var.workload
    environment = "prod"
    owner       = var.owner
    managed_by  = "terraform"
  }
}

# Key Vault and ACR names are global; a short random suffix avoids collisions.
resource "random_string" "unique" {
  length  = 4
  lower   = true
  upper   = false
  numeric = true
  special = false
}

################################################################################
# Resource groups
################################################################################

resource "azurerm_resource_group" "this" {
  for_each = toset(["connectivity", "network", "security", "aks", "data", "ops"])

  name     = "rg-${local.suffix}-${each.key}"
  location = var.location
  tags     = local.tags
}

################################################################################
# Observability
################################################################################

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["ops"].name
  sku                 = "PerGB2018"
  retention_in_days   = 90
  tags                = local.tags
}

resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["ops"].name
  tags                = local.tags
}
