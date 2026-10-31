################################################################################
# Control plane diagnostic logs
################################################################################

resource "azurerm_monitor_diagnostic_setting" "cluster" {
  count = var.log_analytics != null ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id     = var.log_analytics.workspace_id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(var.log_analytics.diagnostic_log_categories)
    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

################################################################################
# Azure Monitor managed Prometheus
################################################################################

resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  count = var.managed_prometheus != null ? 1 : 0

  name                = "dce-prom-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  kind                = "Linux"
  tags                = var.tags
}

resource "azurerm_monitor_data_collection_rule" "prometheus" {
  count = var.managed_prometheus != null ? 1 : 0

  name                        = "dcr-prom-${var.name}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
  tags                        = var.tags

  destinations {
    monitor_account {
      monitor_account_id = var.managed_prometheus.monitor_workspace_id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus" {
  count = var.managed_prometheus != null ? 1 : 0

  name                    = "dcra-prom-${var.name}"
  target_resource_id      = azurerm_kubernetes_cluster.this.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.prometheus[0].id
}

resource "azurerm_monitor_data_collection_rule_association" "prometheus_endpoint" {
  count = var.managed_prometheus != null ? 1 : 0

  # The endpoint association name is fixed by the platform.
  name                        = "configurationAccessEndpoint"
  target_resource_id          = azurerm_kubernetes_cluster.this.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus[0].id
}
