output "virtual_network_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by the logical subnet key. Available only once NSG, egress, peering and DNS wiring exists."
  value       = { for k, s in azurerm_subnet.this : k => s.id }

  # Consumers such as AKS need a working egress path and DNS at creation time.
  depends_on = [
    azurerm_subnet_network_security_group_association.this,
    azurerm_subnet_nat_gateway_association.this,
    azurerm_subnet_route_table_association.firewall,
    azurerm_route.default_via_firewall,
    azurerm_virtual_network_peering.spoke_to_hub,
    azurerm_virtual_network_peering.hub_to_spoke,
    azurerm_private_dns_zone_virtual_network_link.this,
  ]
}

output "route_table_id" {
  description = "ID of the firewall route table, if hub integration is enabled."
  value       = try(azurerm_route_table.firewall[0].id, null)
}

output "network_security_group_ids" {
  description = "NSG IDs keyed by the logical subnet key."
  value       = { for k, n in azurerm_network_security_group.this : k => n.id }
}

output "nat_gateway_id" {
  description = "ID of the NAT gateway, if created."
  value       = try(azurerm_nat_gateway.this[0].id, null)
}

output "nat_gateway_public_ip" {
  description = "Egress public IP of the NAT gateway, if created. Useful for allow-listing on third-party services."
  value       = try(azurerm_public_ip.nat[0].ip_address, null)
}
