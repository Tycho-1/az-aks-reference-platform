################################################################################
# Alerting: recommended metric and Prometheus alerts, health events, budget
################################################################################

data "azurerm_client_config" "current" {}

module "alerting" {
  source = "../../modules/alerting"

  name_prefix         = local.suffix
  resource_group_name = azurerm_resource_group.this["ops"].name
  location            = var.location

  action_group = {
    short_name      = "platformops"
    email_receivers = var.alert_email_receivers
  }

  aks      = { cluster_id = module.aks.id }
  postgres = var.postgres_enabled ? { server_id = module.postgres[0].id } : null
  firewall = { id = module.hub.firewall_id }
  key_vaults = merge(
    { primary = module.key_vault.id },
    var.postgres_enabled ? { paired = module.key_vault_paired[0].id } : {},
  )

  prometheus = {
    monitor_workspace_id = azurerm_monitor_workspace.this.id
    cluster_name         = module.aks.name
  }

  service_health = {
    subscription_id = data.azurerm_client_config.current.subscription_id
    locations       = [var.location, var.paired_location]
  }

  budget = var.monthly_budget == null ? null : {
    subscription_id = data.azurerm_client_config.current.subscription_id
    amount          = var.monthly_budget.amount
    start_date      = var.monthly_budget.start_date
  }

  tags = local.tags
}
