locals {
  suffix  = "${var.workload}-${var.environment}-${var.location_short}"
  is_prod = var.environment == "prod"

  # Carve subnets out of the VNet range: /22 for nodes, /24s for data and private endpoints.
  subnet_cidrs = {
    aks_nodes         = cidrsubnet(var.address_space, 6, 0)
    postgres          = cidrsubnet(var.address_space, 8, 8)
    private_endpoints = cidrsubnet(var.address_space, 8, 9)
  }

  postgres_subnet = var.postgres_enabled ? {
    postgres = {
      name             = "snet-postgres"
      address_prefixes = [local.subnet_cidrs.postgres]
      # Entra ID authentication needs outbound access to login.microsoftonline.com.
      nat_gateway_enabled = true
      # Azure adds this endpoint for WAL archiving; declaring it stops Terraform from removing it.
      service_endpoints = ["Microsoft.Storage"]
      delegation = {
        name    = "postgres"
        service = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
      security_rules = {
        allow-postgres-from-aks = {
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          destination_port_range     = "5432"
          source_address_prefix      = local.subnet_cidrs.aks_nodes
          destination_address_prefix = "*"
        }
        allow-intra-subnet = {
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          destination_port_range     = "*"
          source_address_prefix      = local.subnet_cidrs.postgres
          destination_address_prefix = local.subnet_cidrs.postgres
        }
        deny-vnet-inbound = {
          priority                   = 4000
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          destination_port_range     = "*"
          source_address_prefix      = "VirtualNetwork"
          destination_address_prefix = "*"
        }
      }
    }
  } : {}

  tags = {
    workload    = var.workload
    environment = var.environment
    owner       = var.owner
    managed_by  = "terraform"
  }

  # Nodes reach the public API server via NAT egress; that IP must be authorized too.
  # https://learn.microsoft.com/azure/aks/api-server-authorized-ip-ranges
  # The NAT IP is unknown until apply, so no distinct() or null test here: the list length must stay known at plan time.
  api_server_authorized_ip_ranges = concat(
    var.api_server_authorized_ip_ranges,
    ["${module.network.nat_gateway_public_ip}/32"],
  )
}

################################################################################
# Resource groups (one per lifecycle / ownership boundary)
################################################################################

resource "azurerm_resource_group" "network" {
  name     = "rg-${local.suffix}-network"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "aks" {
  name     = "rg-${local.suffix}-aks"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "data" {
  name     = "rg-${local.suffix}-data"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "ops" {
  name     = "rg-${local.suffix}-ops"
  location = var.location
  tags     = local.tags
}

################################################################################
# Observability
################################################################################

resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${local.suffix}"
  location            = azurerm_resource_group.ops.location
  resource_group_name = azurerm_resource_group.ops.name
  sku                 = "PerGB2018"
  retention_in_days   = local.is_prod ? 90 : 30
  tags                = local.tags
}

resource "azurerm_monitor_workspace" "this" {
  name                = "amw-${local.suffix}"
  location            = azurerm_resource_group.ops.location
  resource_group_name = azurerm_resource_group.ops.name
  tags                = local.tags
}

################################################################################
# Network
################################################################################

module "network" {
  source = "../../modules/network"

  name                = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.network.name
  location            = var.location
  address_space       = [var.address_space]

  nat_gateway = {
    name = "ng-${local.suffix}"
  }

  subnets = merge(
    {
      aks_nodes = {
        name                = "snet-aks-nodes"
        address_prefixes    = [local.subnet_cidrs.aks_nodes]
        nat_gateway_enabled = true
        security_rules = {
          # Public ingress through the cluster's load balancer. Remove for internal-only clusters.
          allow-https-inbound = {
            priority                   = 100
            direction                  = "Inbound"
            access                     = "Allow"
            protocol                   = "Tcp"
            destination_port_ranges    = ["80", "443"]
            source_address_prefix      = "Internet"
            destination_address_prefix = "*"
          }
        }
      }
      private_endpoints = {
        name             = "snet-private-endpoints"
        address_prefixes = [local.subnet_cidrs.private_endpoints]
      }
    },
    local.postgres_subnet,
  )

  tags = local.tags
}

################################################################################
# AKS
################################################################################

module "aks" {
  source = "../../modules/aks"

  name                = "aks-${local.suffix}"
  resource_group_name = azurerm_resource_group.aks.name
  location            = var.location
  kubernetes_version  = var.kubernetes_version
  sku_tier            = local.is_prod ? "Standard" : "Free"

  node_subnet_id = module.network.subnet_ids["aks_nodes"]
  network_profile = {
    outbound_type = "userAssignedNATGateway"
  }

  admin_group_object_ids          = var.aks_admin_group_object_ids
  api_server_authorized_ip_ranges = local.api_server_authorized_ip_ranges

  system_node_pool = {
    min_count = 1
    max_count = 2
    zones     = var.node_availability_zones
    # Sandbox: Dds_v5 quota often 0 on idle subs; B2s Spot lacks capacity in some regions. Dsv3 + Regular + Managed.
    vm_size      = "Standard_D2s_v3"
    os_disk_type = "Managed"
  }

  node_pools = {
    apps = {
      vm_size      = "Standard_D2s_v3"
      os_disk_type = "Managed"
      zones        = var.node_availability_zones
      priority     = "Regular"
      min_count    = local.is_prod ? 3 : 1
      max_count    = local.is_prod ? 10 : 3
      node_labels = {
        "workload-class" = "general"
      }
    }
  }

  log_analytics = {
    workspace_id     = azurerm_log_analytics_workspace.this.id
    defender_enabled = local.is_prod
  }

  managed_prometheus = {
    monitor_workspace_id = azurerm_monitor_workspace.this.id
  }

  tags = local.tags
}

################################################################################
# PostgreSQL
################################################################################

module "postgres" {
  count  = var.postgres_enabled ? 1 : 0
  source = "../../modules/postgresql-flexible-server"

  name                = "psql-${local.suffix}"
  resource_group_name = azurerm_resource_group.data.name
  location            = var.location

  sku_name                     = local.is_prod ? "GP_Standard_D4ds_v5" : "B_Standard_B2s"
  high_availability            = local.is_prod ? {} : null
  geo_redundant_backup_enabled = local.is_prod
  backup_retention_days        = local.is_prod ? 35 : 7
  delete_lock_enabled          = local.is_prod

  delegated_subnet_id = module.network.subnet_ids["postgres"]
  private_dns_zone = {
    virtual_network_ids = {
      (module.network.virtual_network_name) = module.network.virtual_network_id
    }
  }

  entra_administrator = {
    object_id      = var.postgres_admin_group.object_id
    principal_name = var.postgres_admin_group.display_name
    principal_type = "Group"
  }

  databases = {
    app = {}
  }
  extensions = ["PG_TRGM", "UUID-OSSP"]

  log_analytics_workspace = {
    id = azurerm_log_analytics_workspace.this.id
  }

  tags = local.tags
}
