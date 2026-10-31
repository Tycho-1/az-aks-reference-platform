output "virtual_network_id" {
  description = "ID of the hub VNet."
  value       = azurerm_virtual_network.this.id
}

output "virtual_network_name" {
  description = "Name of the hub VNet."
  value       = azurerm_virtual_network.this.name
}

output "firewall_id" {
  description = "ID of the Azure Firewall."
  value       = azurerm_firewall.this.id
}

output "firewall_private_ip" {
  description = "Private IP of the firewall: next hop for spoke default routes and DNS server for spokes."
  value       = azurerm_firewall.this.ip_configuration[0].private_ip_address
}

output "firewall_public_ip" {
  description = "Egress public IP of the firewall. Allow-list this on third-party services."
  value       = azurerm_public_ip.firewall.ip_address
}

output "firewall_policy_id" {
  description = "ID of the firewall policy, for adding workload-specific rule collection groups."
  value       = azurerm_firewall_policy.this.id
}

output "private_dns_zone_ids" {
  description = "Central private DNS zone IDs keyed by logical name."
  value       = { for k, z in azurerm_private_dns_zone.this : k => z.id }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.hub,
  ]
}

output "subnet_ids" {
  description = "IDs of the additional hub subnets keyed by logical name."
  value       = { for k, s in azurerm_subnet.additional : k => s.id }
}

output "bastion_host_id" {
  description = "ID of the Azure Bastion host when `bastion` is set; null otherwise."
  value       = try(azurerm_bastion_host.this[0].id, null)
}

output "bastion_host_name" {
  description = "Name of the Azure Bastion host when `bastion` is set; null otherwise."
  value       = try(azurerm_bastion_host.this[0].name, null)
}

output "vpn_gateway_id" {
  description = "ID of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise."
  value       = try(azurerm_virtual_network_gateway.vpn[0].id, null)
}

output "vpn_gateway_name" {
  description = "Name of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise."
  value       = try(azurerm_virtual_network_gateway.vpn[0].name, null)
}

output "vpn_gateway_public_ip" {
  description = "Public IP of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise."
  value       = try(azurerm_public_ip.vpn[0].ip_address, null)
}
