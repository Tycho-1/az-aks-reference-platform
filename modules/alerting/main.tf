locals {
  # Thresholds follow the Azure Monitor recommended alert rules for each service.
  aks_alerts = {
    aks-node-cpu = {
      scope       = try(var.aks.cluster_id, null)
      namespace   = "Microsoft.ContainerService/managedClusters"
      metric      = "node_cpu_usage_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "Average node CPU above threshold: scale the node pool or check noisy workloads."
    }
    aks-node-memory = {
      scope       = try(var.aks.cluster_id, null)
      namespace   = "Microsoft.ContainerService/managedClusters"
      metric      = "node_memory_working_set_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "Node memory working set above threshold: risk of OOM kills and evictions."
    }
    aks-node-disk = {
      scope       = try(var.aks.cluster_id, null)
      namespace   = "Microsoft.ContainerService/managedClusters"
      metric      = "node_disk_usage_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "Node OS disk usage above threshold: image garbage collection or larger OS disks needed."
    }
    aks-unschedulable-pods = {
      scope       = try(var.aks.cluster_id, null)
      namespace   = "Microsoft.ContainerService/managedClusters"
      metric      = "cluster_autoscaler_unschedulable_pods_count"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 0
      severity    = 3
      frequency   = "PT5M"
      window      = "PT30M"
      description = "Pods remain unschedulable: the autoscaler hit max_count, quota, or a constraint it can't satisfy."
    }
  }

  postgres_alerts = {
    postgres-availability = {
      scope       = try(var.postgres.server_id, null)
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      metric      = "is_db_alive"
      aggregation = "Maximum"
      operator    = "LessThan"
      threshold   = 1
      severity    = 0
      frequency   = "PT1M"
      window      = "PT5M"
      description = "The PostgreSQL server is not responding."
    }
    postgres-cpu = {
      scope       = try(var.postgres.server_id, null)
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      metric      = "cpu_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "PostgreSQL CPU above threshold: check slow queries or scale the SKU."
    }
    postgres-memory = {
      scope       = try(var.postgres.server_id, null)
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      metric      = "memory_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 90
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "PostgreSQL memory above threshold."
    }
    postgres-storage = {
      scope       = try(var.postgres.server_id, null)
      namespace   = "Microsoft.DBforPostgreSQL/flexibleServers"
      metric      = "storage_percent"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 1
      frequency   = "PT15M"
      window      = "PT1H"
      description = "PostgreSQL storage above threshold. A full server becomes read-only; verify auto-grow and tier limits."
    }
  }

  firewall_alerts = {
    firewall-health = {
      scope       = try(var.firewall.id, null)
      namespace   = "Microsoft.Network/azureFirewalls"
      metric      = "FirewallHealth"
      aggregation = "Average"
      operator    = "LessThan"
      threshold   = 90
      severity    = 1
      frequency   = "PT5M"
      window      = "PT15M"
      description = "Azure Firewall health degraded: all spoke egress depends on it."
    }
    firewall-snat = {
      scope       = try(var.firewall.id, null)
      namespace   = "Microsoft.Network/azureFirewalls"
      metric      = "SNATPortUtilization"
      aggregation = "Maximum"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      frequency   = "PT5M"
      window      = "PT15M"
      description = "Firewall SNAT port utilisation high: add public IPs or a NAT gateway on the firewall subnet."
    }
  }

  key_vault_alerts = merge([
    for name, id in var.key_vaults : {
      "kv-${name}-availability" = {
        scope       = id
        namespace   = "Microsoft.KeyVault/vaults"
        metric      = "Availability"
        aggregation = "Average"
        operator    = "LessThan"
        threshold   = 99
        severity    = 1
        frequency   = "PT5M"
        window      = "PT15M"
        description = "Key Vault availability dropped. CMK-encrypted services can't unwrap keys while it's unavailable."
      }
      "kv-${name}-saturation" = {
        scope       = id
        namespace   = "Microsoft.KeyVault/vaults"
        metric      = "SaturationShoebox"
        aggregation = "Average"
        operator    = "GreaterThan"
        threshold   = 75
        severity    = 2
        frequency   = "PT5M"
        window      = "PT15M"
        description = "Key Vault close to its request throttling limit."
      }
    }
  ]...)

  default_alerts = merge(
    { for k, v in local.aks_alerts : k => v if var.aks != null },
    { for k, v in local.postgres_alerts : k => v if var.postgres != null },
    { for k, v in local.firewall_alerts : k => v if var.firewall != null },
    local.key_vault_alerts,
  )

  metric_alerts = {
    for k, v in local.default_alerts : k => merge(v, {
      threshold = try(coalesce(var.alert_overrides[k].threshold, v.threshold), v.threshold)
      severity  = try(coalesce(var.alert_overrides[k].severity, v.severity), v.severity)
      enabled   = try(coalesce(var.alert_overrides[k].enabled, true), true)
    })
  }

  resource_health_scopes = compact(concat(
    [try(var.aks.cluster_id, null), try(var.postgres.server_id, null), try(var.firewall.id, null)],
    values(var.key_vaults),
  ))
  resource_health_enabled = var.resource_health_enabled && (var.aks != null || var.postgres != null || var.firewall != null || length(var.key_vaults) > 0)
}

resource "azurerm_monitor_action_group" "this" {
  name                = "ag-${var.name_prefix}"
  resource_group_name = var.resource_group_name
  short_name          = var.action_group.short_name
  tags                = var.tags

  dynamic "email_receiver" {
    for_each = var.action_group.email_receivers
    content {
      name                    = email_receiver.key
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }

  dynamic "webhook_receiver" {
    for_each = var.action_group.webhook_receivers
    content {
      name                    = webhook_receiver.key
      service_uri             = webhook_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "this" {
  for_each = local.metric_alerts

  name                = "alert-${var.name_prefix}-${each.key}"
  resource_group_name = var.resource_group_name
  scopes              = [each.value.scope]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window
  enabled             = each.value.enabled
  auto_mitigate       = true
  tags                = var.tags

  criteria {
    metric_namespace = each.value.namespace
    metric_name      = each.value.metric
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "resource_health" {
  count = local.resource_health_enabled ? 1 : 0

  name                = "alert-${var.name_prefix}-resource-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = local.resource_health_scopes
  description         = "A platform resource became Degraded or Unavailable."
  tags                = var.tags

  criteria {
    category = "ResourceHealth"

    resource_health {
      current  = ["Degraded", "Unavailable"]
      previous = ["Available"]
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  count = var.service_health != null ? 1 : 0

  name                = "alert-${var.name_prefix}-service-health"
  resource_group_name = var.resource_group_name
  location            = "global"
  scopes              = ["/subscriptions/${var.service_health.subscription_id}"]
  description         = "Azure service incident, planned maintenance or security advisory in the platform regions."
  tags                = var.tags

  criteria {
    category = "ServiceHealth"

    service_health {
      events    = ["Incident", "Maintenance", "Security", "ActionRequired"]
      locations = concat(var.service_health.locations, ["Global"])
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.this.id
  }
}

resource "azurerm_consumption_budget_subscription" "this" {
  count = var.budget != null ? 1 : 0

  name            = "budget-${var.name_prefix}"
  subscription_id = "/subscriptions/${var.budget.subscription_id}"
  amount          = var.budget.amount
  time_grain      = "Monthly"

  time_period {
    start_date = var.budget.start_date
  }

  dynamic "notification" {
    for_each = toset(var.budget.actual_thresholds)
    content {
      operator       = "GreaterThanOrEqualTo"
      threshold      = notification.value
      threshold_type = "Actual"
      contact_emails = var.budget.contact_emails
      contact_groups = [azurerm_monitor_action_group.this.id]
    }
  }

  notification {
    operator       = "GreaterThanOrEqualTo"
    threshold      = var.budget.forecast_threshold
    threshold_type = "Forecasted"
    contact_emails = var.budget.contact_emails
    contact_groups = [azurerm_monitor_action_group.this.id]
  }
}
