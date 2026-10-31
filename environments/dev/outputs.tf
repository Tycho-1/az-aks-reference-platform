output "aks_name" {
  value = module.aks.name
}

output "aks_get_credentials" {
  value = module.aks.get_credentials_command
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "egress_public_ip" {
  description = "Allow-list this IP on third-party services the cluster calls."
  value       = module.network.nat_gateway_public_ip
}

output "postgres_fqdn" {
  description = "Null when postgres_enabled is false."
  value       = try(module.postgres[0].fqdn, null)
}
