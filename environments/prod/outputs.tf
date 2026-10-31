output "aks_name" {
  value = module.aks.name
}

output "aks_command_invoke_example" {
  description = "The API server is private; run kubectl through the AKS control plane without network line of sight."
  value       = "az aks command invoke -g ${azurerm_resource_group.this["aks"].name} -n ${module.aks.name} --command 'kubectl get nodes'"
}

output "operator_access" {
  description = "Ways to reach private resources after deploy. Bastion is in the hub connectivity resource group. vpn_gateway_name is null unless vpn_gateway_enabled is true."
  value = {
    bastion_host_name      = module.hub.bastion_host_name
    bastion_resource_group = azurerm_resource_group.this["connectivity"].name
    vpn_gateway_name       = module.hub.vpn_gateway_name
    aks_command_invoke     = "az aks command invoke -g ${azurerm_resource_group.this["aks"].name} -n ${module.aks.name} --command 'kubectl get nodes'"
    terraform_runner_hint  = "Set GitHub variable TERRAFORM_RUNNER to a self-hosted runner in the spoke, or run Terraform from a VM reached via Bastion."
  }
}

output "aks_oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "acr_login_server" {
  value = module.acr.login_server
}

output "egress_public_ip" {
  description = "All spoke egress leaves through this firewall IP."
  value       = module.hub.firewall_public_ip
}

output "postgres_fqdn" {
  description = "Null when postgres_enabled is false."
  value       = var.postgres_enabled ? module.postgres[0].fqdn : null
}

output "sample_api_workload_identity" {
  description = "Values for gitops/apps/production and the PostgreSQL role of the sample API."
  value = {
    client_id     = azurerm_user_assigned_identity.sample_api.client_id
    postgres_role = "SELECT * FROM pgaadauth_create_principal('${azurerm_user_assigned_identity.sample_api.name}', false, false);"
  }
}
