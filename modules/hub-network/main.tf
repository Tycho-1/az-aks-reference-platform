resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

resource "azurerm_subnet" "firewall" {
  # Name is mandated by Azure Firewall.
  name                            = "AzureFirewallSubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.firewall.subnet_address_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "additional" {
  for_each = var.additional_subnets

  name                            = each.value.name
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = each.value.address_prefixes
  default_outbound_access_enabled = false
}

resource "azurerm_subnet" "bastion" {
  count = var.bastion != null ? 1 : 0

  # Name is mandated by Azure Bastion.
  name                            = "AzureBastionSubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.bastion.subnet_address_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "bastion" {
  count = var.bastion != null ? 1 : 0

  name                = "pip-${var.bastion.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.firewall.zones
  tags                = var.tags
}

resource "azurerm_bastion_host" "this" {
  count = var.bastion != null ? 1 : 0

  name                = var.bastion.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.bastion.sku
  scale_units         = var.bastion.scale_units
  copy_paste_enabled  = false
  file_copy_enabled   = false
  tags                = var.tags

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion[0].id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }
}

resource "azurerm_monitor_diagnostic_setting" "bastion" {
  count = var.bastion != null && var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.bastion.name}"
  target_resource_id             = azurerm_bastion_host.this[0].id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

################################################################################
# Point-to-site VPN
################################################################################

resource "azurerm_subnet" "gateway" {
  count = var.vpn_gateway != null ? 1 : 0

  # Name is mandated by Azure VPN Gateway.
  name                            = "GatewaySubnet"
  resource_group_name             = var.resource_group_name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.vpn_gateway.subnet_address_prefix]
  default_outbound_access_enabled = false
}

resource "azurerm_public_ip" "vpn" {
  count = var.vpn_gateway != null ? 1 : 0

  name                = "pip-${var.vpn_gateway.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = length(var.vpn_gateway.zones) > 0 ? var.vpn_gateway.zones : null
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count = var.vpn_gateway != null ? 1 : 0

  name                = var.vpn_gateway.name
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_gateway.sku
  generation          = var.vpn_gateway.generation
  active_active       = false
  bgp_enabled         = false
  tags                = var.tags

  ip_configuration {
    name                          = "default"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway[0].id
  }

  # Entra ID over OpenVPN. The audience is the public Azure VPN app.
  # Clients do not receive the hub private DNS zones through this tunnel.
  vpn_client_configuration {
    address_space        = var.vpn_gateway.client_address_space
    vpn_client_protocols = ["OpenVPN"]
    vpn_auth_types       = ["AAD"]
    aad_tenant           = "https://login.microsoftonline.com/${var.vpn_gateway.tenant_id}/"
    aad_audience         = var.vpn_gateway.aad_audience
    aad_issuer           = "https://sts.windows.net/${var.vpn_gateway.tenant_id}/"
  }
}

resource "azurerm_monitor_diagnostic_setting" "vpn" {
  count = var.vpn_gateway != null && var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.vpn_gateway.name}"
  target_resource_id             = azurerm_virtual_network_gateway.vpn[0].id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

################################################################################
# Azure Firewall
################################################################################

resource "azurerm_public_ip" "firewall" {
  name                = "pip-${var.firewall.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.firewall.zones
  tags                = var.tags
}

resource "azurerm_firewall_policy" "this" {
  name                     = "afwp-${var.firewall.name}"
  location                 = var.location
  resource_group_name      = var.resource_group_name
  sku                      = var.firewall.sku_tier
  threat_intelligence_mode = var.firewall.threat_intel_mode
  tags                     = var.tags

  # DNS proxy lets spokes use the firewall as their DNS server, which is required for FQDN
  # network rules and gives a single resolution path to the hub's private DNS zones.
  dns {
    proxy_enabled = true
  }

  dynamic "intrusion_detection" {
    for_each = var.firewall.sku_tier == "Premium" ? [1] : []
    content {
      mode = var.firewall.idps_mode
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = var.firewall.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall.sku_tier
  firewall_policy_id  = azurerm_firewall_policy.this.id
  zones               = var.firewall.zones
  tags                = var.tags

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "aks" {
  count = var.aks_egress != null ? 1 : 0

  name               = "aks-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 200

  network_rule_collection {
    name     = "aks-network"
    priority = 100
    action   = "Allow"

    # Tunnel ports are only used by clusters without Konnectivity or API server VNet integration.
    rule {
      name                  = "api-server-tunnel"
      protocols             = ["TCP", "UDP"]
      source_addresses      = var.aks_egress.source_addresses
      destination_addresses = ["AzureCloud.${var.location}"]
      destination_ports     = ["1194", "9000"]
    }

    rule {
      name              = "ntp"
      protocols         = ["UDP"]
      source_addresses  = var.aks_egress.source_addresses
      destination_fqdns = ["ntp.ubuntu.com"]
      destination_ports = ["123"]
    }

    rule {
      name                  = "azure-monitor"
      protocols             = ["TCP"]
      source_addresses      = var.aks_egress.source_addresses
      destination_addresses = ["AzureMonitor"]
      destination_ports     = ["443"]
    }
  }

  application_rule_collection {
    name     = "aks-application"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "aks-required"
      source_addresses      = var.aks_egress.source_addresses
      destination_fqdn_tags = ["AzureKubernetesService"]

      protocols {
        type = "Https"
        port = 443
      }

      protocols {
        type = "Http"
        port = 80
      }
    }

    dynamic "rule" {
      for_each = length(var.aks_egress.additional_fqdns) > 0 ? [1] : []
      content {
        name              = "additional"
        source_addresses  = var.aks_egress.source_addresses
        destination_fqdns = var.aks_egress.additional_fqdns

        protocols {
          type = "Https"
          port = 443
        }
      }
    }
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "platform" {
  count = length(var.additional_network_rules) > 0 ? 1 : 0

  name               = "platform-egress"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 300

  network_rule_collection {
    name     = "platform-network"
    priority = 100
    action   = "Allow"

    dynamic "rule" {
      for_each = var.additional_network_rules
      content {
        name                  = rule.key
        protocols             = rule.value.protocols
        source_addresses      = rule.value.source_addresses
        destination_addresses = rule.value.destination_addresses
        destination_ports     = rule.value.destination_ports
      }
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.firewall.name}"
  target_resource_id             = azurerm_firewall.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

################################################################################
# Central private DNS
################################################################################

resource "azurerm_private_dns_zone" "this" {
  for_each = var.private_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each = var.private_dns_zones

  name                = "link-${var.name}"
  private_dns_zone_id = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = var.tags
}
