output "id" {
  description = "Resource ID of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.id
}

output "name" {
  description = "Name of the AKS cluster."
  value       = azurerm_kubernetes_cluster.this.name
}

output "fqdn" {
  description = "Public FQDN of the API server (null for private clusters without a public FQDN)."
  value       = azurerm_kubernetes_cluster.this.fqdn
}

output "private_fqdn" {
  description = "Private FQDN of the API server (private clusters only)."
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "current_kubernetes_version" {
  description = "Kubernetes version currently running, including auto-applied patches."
  value       = azurerm_kubernetes_cluster.this.current_kubernetes_version
}

output "node_resource_group" {
  description = "Name of the AKS-managed node resource group."
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL, used to create federated credentials for workload identity."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "web_app_routing_enabled" {
  description = "True when the managed application routing add-on is enabled."
  value       = var.web_app_routing != null
}

output "node_pool_priorities" {
  description = "Priority of each user node pool (Regular or Spot)."
  value       = { for k, v in azurerm_kubernetes_cluster_node_pool.this : k => v.priority }
}

output "node_pool_vm_sizes" {
  description = "VM size of each user node pool."
  value       = { for k, v in azurerm_kubernetes_cluster_node_pool.this : k => v.vm_size }
}

output "system_node_pool_vm_size" {
  description = "VM size of the system node pool."
  value       = azurerm_kubernetes_cluster.this.default_node_pool[0].vm_size
}

output "control_plane_identity" {
  description = "User-assigned identity of the cluster control plane."
  value = {
    id           = azurerm_user_assigned_identity.control_plane.id
    principal_id = azurerm_user_assigned_identity.control_plane.principal_id
    client_id    = azurerm_user_assigned_identity.control_plane.client_id
  }
}

output "kubelet_identity" {
  description = "User-assigned identity used by the kubelet (e.g. for AcrPull)."
  value = {
    id           = azurerm_user_assigned_identity.kubelet.id
    principal_id = azurerm_user_assigned_identity.kubelet.principal_id
    client_id    = azurerm_user_assigned_identity.kubelet.client_id
  }
}

output "key_vault_secrets_provider_identity" {
  description = "Identity of the Key Vault Secrets Store CSI driver add-on, if enabled."
  value       = try(azurerm_kubernetes_cluster.this.key_vault_secrets_provider[0].secret_identity[0], null)
}

output "get_credentials_command" {
  description = "Command to fetch a kubeconfig that authenticates through Entra ID (requires kubelogin)."
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.this.name} && kubelogin convert-kubeconfig -l azurecli"
}
