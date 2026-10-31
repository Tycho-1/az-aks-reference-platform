################################################################################
# Workload identity for the sample API (gitops/apps/base/sample-api)
#
# The Kubernetes service account sample-api/sample-api exchanges its projected token for an
# Entra ID token of this identity: no secrets in the cluster.
################################################################################

resource "azurerm_user_assigned_identity" "sample_api" {
  name                = "id-${local.suffix}-sample-api"
  location            = var.location
  resource_group_name = azurerm_resource_group.this["aks"].name
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "sample_api" {
  name                      = "aks-sample-api"
  user_assigned_identity_id = azurerm_user_assigned_identity.sample_api.id
  issuer                    = module.aks.oidc_issuer_url
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "system:serviceaccount:sample-api:sample-api"
}
