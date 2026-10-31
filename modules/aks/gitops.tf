resource "azurerm_kubernetes_cluster_extension" "flux" {
  count = var.gitops != null ? 1 : 0

  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.flux"
}

resource "azurerm_kubernetes_flux_configuration" "platform" {
  count = var.gitops != null ? 1 : 0

  name       = "platform"
  cluster_id = azurerm_kubernetes_cluster.this.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url             = var.gitops.repository_url
    reference_type  = "branch"
    reference_value = var.gitops.branch
  }

  dynamic "kustomizations" {
    for_each = var.gitops.kustomizations
    content {
      name                       = kustomizations.key
      path                       = kustomizations.value.path
      depends_on                 = kustomizations.value.depends_on
      garbage_collection_enabled = kustomizations.value.prune
    }
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}
