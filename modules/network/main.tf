locals {
  nsg_subnets = { for k, s in var.subnets : k => s if s.nsg_enabled }
  nat_subnets = { for k, s in var.subnets : k => s if s.nat_gateway_enabled && var.nat_gateway != null }
  fw_subnets  = { for k, s in var.subnets : k => s if s.route_via_firewall && var.hub != null }

  hub_vnet = var.hub == null ? null : {
    resource_group_name = regex("/resourceGroups/([^/]+)/", var.hub.virtual_network_id)[0]
    name                = regex("/virtualNetworks/([^/]+)$", var.hub.virtual_network_id)[0]
  }

  security_rules = merge([
    for subnet_key, s in local.nsg_subnets : {
      for rule_name, rule in s.security_rules : "${subnet_key}/${rule_name}" => merge(rule, {
        subnet_key = subnet_key
        name       = rule_name
      })
    }
  ]...)
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  dns_servers         = var.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.value.name
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = each.value.address_prefixes

  # Default outbound access is being retired; egress must be explicit (NAT gateway, LB or firewall).
  default_outbound_access_enabled   = false
  private_endpoint_network_policies = each.value.private_endpoint_network_policies

  dynamic "service_endpoint" {
    for_each = toset(each.value.service_endpoints)
    content {
      service = service_endpoint.value
    }
  }

  dynamic "delegation" {
    for_each = each.value.delegation != null ? [each.value.delegation] : []
    content {
      name = delegation.value.name
      service_delegation {
        name    = delegation.value.service
        actions = delegation.value.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.nsg_subnets

  name                = "nsg-${each.value.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "this" {
  for_each = local.security_rules

  name                         = each.value.name
  resource_group_name          = var.resource_group_name
  network_security_group_name  = azurerm_network_security_group.this[each.value.subnet_key].name
  priority                     = each.value.priority
  direction                    = each.value.direction
  access                       = each.value.access
  protocol                     = each.value.protocol
  description                  = each.value.description
  source_port_range            = each.value.source_port_range
  destination_port_range       = each.value.destination_port_range
  destination_port_ranges      = each.value.destination_port_ranges
  source_address_prefix        = each.value.source_address_prefix
  source_address_prefixes      = each.value.source_address_prefixes
  destination_address_prefix   = each.value.destination_address_prefix
  destination_address_prefixes = each.value.destination_address_prefixes
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.nsg_subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}

resource "azurerm_public_ip" "nat" {
  count = var.nat_gateway != null ? 1 : 0

  name                = "pip-${var.nat_gateway.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.nat_gateway.zones
  tags                = var.tags
}

resource "azurerm_nat_gateway" "this" {
  count = var.nat_gateway != null ? 1 : 0

  name                    = var.nat_gateway.name
  location                = var.location
  resource_group_name     = var.resource_group_name
  sku_name                = "Standard"
  idle_timeout_in_minutes = var.nat_gateway.idle_timeout_in_minutes
  zones                   = var.nat_gateway.zones
  tags                    = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "this" {
  count = var.nat_gateway != null ? 1 : 0

  nat_gateway_id       = azurerm_nat_gateway.this[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "this" {
  for_each = local.nat_subnets

  subnet_id      = azurerm_subnet.this[each.key].id
  nat_gateway_id = azurerm_nat_gateway.this[0].id
}

################################################################################
# Hub integration
################################################################################

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  count = var.hub != null ? 1 : 0

  name                      = "peer-${var.name}-to-${local.hub_vnet.name}"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub.virtual_network_id
  allow_forwarded_traffic   = true
}

resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count = var.hub != null ? 1 : 0

  name                      = "peer-${local.hub_vnet.name}-to-${var.name}"
  resource_group_name       = local.hub_vnet.resource_group_name
  virtual_network_name      = local.hub_vnet.name
  remote_virtual_network_id = azurerm_virtual_network.this.id
  allow_forwarded_traffic   = true
}

resource "azurerm_route_table" "firewall" {
  count = var.hub != null ? 1 : 0

  name                = "rt-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  # Stop on-premises/BGP routes from bypassing the firewall.
  bgp_route_propagation_enabled = false
  tags                          = var.tags
}

resource "azurerm_route" "default_via_firewall" {
  count = var.hub != null ? 1 : 0

  name                   = "default-via-firewall"
  resource_group_name    = var.resource_group_name
  route_table_name       = azurerm_route_table.firewall[0].name
  address_prefix         = "0.0.0.0/0"
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.hub.firewall_private_ip
}

resource "azurerm_subnet_route_table_association" "firewall" {
  for_each = local.fw_subnets

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.firewall[0].id
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = var.private_dns_zone_links

  name                = "link-${var.name}"
  private_dns_zone_id = each.value
  virtual_network_id  = azurerm_virtual_network.this.id
  tags                = var.tags
}
