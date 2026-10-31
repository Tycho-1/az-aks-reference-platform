################################################################################
# Hub: Azure Firewall, DNS proxy, central private DNS zones
################################################################################

module "hub" {
  source = "../../modules/hub-network"

  name                = "vnet-hub-prod-${var.location_short}"
  resource_group_name = azurerm_resource_group.this["connectivity"].name
  location            = var.location
  address_space       = [var.hub_address_space]

  # zones = [] is the off switch. null is not: the module's optional() default would
  # restore ["1", "2", "3"]. North Europe rejected Standard firewall zones 1-3
  # (AzureFirewallUnsupportedAvailabilityZone). The same list is applied to the
  # firewall and Bastion public IPs. This root stays non-zonal because that is
  # the layout the smoke test applied.
  firewall = {
    name                  = "afw-hub-prod-${var.location_short}"
    subnet_address_prefix = cidrsubnet(var.hub_address_space, 4, 0)
    sku_tier              = "Standard"
    zones                 = []
  }

  bastion = {
    name                  = "bas-hub-prod-${var.location_short}"
    subnet_address_prefix = cidrsubnet(var.hub_address_space, 4, 1)
  }

  # Index 2 is the next /26 after the firewall (0) and Bastion (1): 10.0.0.128/26 on the default hub.
  # The client pool must stay outside the hub, spoke, pod, and service CIDRs.
  vpn_gateway = var.vpn_gateway_enabled ? {
    name                  = "vpng-hub-prod-${var.location_short}"
    subnet_address_prefix = cidrsubnet(var.hub_address_space, 4, 2)
    client_address_space  = ["172.16.201.0/24"]
    tenant_id             = data.azurerm_client_config.current.tenant_id
  } : null

  private_dns_zones = {
    acr       = "privatelink.azurecr.io"
    key_vault = "privatelink.vaultcore.azure.net"
    aks       = "privatelink.${var.location}.azmk8s.io"
    postgres  = "private.postgres.database.azure.com"
  }

  aks_egress = {
    source_addresses = [local.spoke_subnets.aks_nodes]
    additional_fqdns = local.gitops_egress_fqdns
  }

  additional_network_rules = {
    postgres-entra-auth = {
      source_addresses      = [local.spoke_subnets.postgres]
      destination_addresses = ["AzureActiveDirectory"]
      destination_ports     = ["443"]
    }
  }

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
  tags                    = local.tags
}

################################################################################
# Spoke: workload network, all egress through the hub firewall
################################################################################

module "spoke" {
  source = "../../modules/network"

  name                = "vnet-${local.suffix}"
  resource_group_name = azurerm_resource_group.this["network"].name
  location            = var.location
  address_space       = [var.spoke_address_space]

  # The firewall DNS proxy resolves the hub's private DNS zones for the spoke.
  dns_servers = [module.hub.firewall_private_ip]

  hub = {
    virtual_network_id  = module.hub.virtual_network_id
    firewall_private_ip = module.hub.firewall_private_ip
  }

  # AKS links the private cluster zone itself; PostgreSQL needs its zone linked to the spoke.
  private_dns_zone_links = {
    postgres = module.hub.private_dns_zone_ids["postgres"]
  }

  subnets = {
    aks_nodes = {
      name               = "snet-aks-nodes"
      address_prefixes   = [local.spoke_subnets.aks_nodes]
      route_via_firewall = true
    }

    aks_apiserver = {
      name             = "snet-aks-apiserver"
      address_prefixes = [local.spoke_subnets.aks_apiserver]
      delegation = {
        name    = "aks"
        service = "Microsoft.ContainerService/managedClusters"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }

    postgres = {
      name               = "snet-postgres"
      address_prefixes   = [local.spoke_subnets.postgres]
      route_via_firewall = true
      # Azure adds this endpoint for WAL archiving (it also bypasses the firewall route); declare it so Terraform keeps it.
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
          source_address_prefix      = local.spoke_subnets.aks_nodes
          destination_address_prefix = "*"
        }
        allow-intra-subnet = {
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "*"
          destination_port_range     = "*"
          source_address_prefix      = local.spoke_subnets.postgres
          destination_address_prefix = local.spoke_subnets.postgres
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

    private_endpoints = {
      name             = "snet-private-endpoints"
      address_prefixes = [local.spoke_subnets.private_endpoints]
    }
  }

  tags = local.tags
}
