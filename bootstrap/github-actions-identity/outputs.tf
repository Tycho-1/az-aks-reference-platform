output "github_variables" {
  description = "Values for the GitHub repository/environment variables used by the deploy workflow."
  value = {
    AZURE_TENANT_ID       = data.azurerm_subscription.current.tenant_id
    AZURE_SUBSCRIPTION_ID = data.azurerm_subscription.current.subscription_id
    AZURE_CLIENT_ID_PLAN  = azurerm_user_assigned_identity.this["plan"].client_id
    AZURE_CLIENT_ID_APPLY = azurerm_user_assigned_identity.this["apply"].client_id
  }
}
