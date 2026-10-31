mock_provider "azurerm" {}

variables {
  name_prefix         = "platform-test-weu"
  resource_group_name = "rg-ops"
  location            = "westeurope"

  action_group = {
    short_name      = "platform"
    email_receivers = { oncall = "oncall@example.com" }
  }
}

run "action_group_only" {
  command = plan

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 0 && length(azurerm_monitor_activity_log_alert.resource_health) == 0
    error_message = "No alerts should exist without targets."
  }
}

run "all_targets" {
  command = plan

  variables {
    aks        = { cluster_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aks/providers/Microsoft.ContainerService/managedClusters/aks-test" }
    postgres   = { server_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-data/providers/Microsoft.DBforPostgreSQL/flexibleServers/psql-test" }
    firewall   = { id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/azureFirewalls/afw-test" }
    key_vaults = { primary = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-test" }
    prometheus = {
      monitor_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-ops/providers/Microsoft.Monitor/accounts/amw-test"
      cluster_name         = "aks-test"
    }
    service_health = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      locations       = ["West Europe"]
    }
    budget = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      amount          = 3000
      start_date      = "2026-10-01T00:00:00Z"
    }
    alert_overrides = {
      postgres-cpu           = { threshold = 70 }
      aks-unschedulable-pods = { enabled = false }
    }
  }

  assert {
    condition     = length(azurerm_monitor_metric_alert.this) == 12
    error_message = "Expected 4 AKS, 4 PostgreSQL, 2 firewall and 2 Key Vault alerts."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["postgres-cpu"].criteria[0].threshold == 70
    error_message = "Threshold overrides should apply."
  }

  assert {
    condition     = !azurerm_monitor_metric_alert.this["aks-unschedulable-pods"].enabled && azurerm_monitor_metric_alert.this["aks-node-cpu"].enabled
    error_message = "Only the overridden alert should be disabled."
  }

  assert {
    condition     = azurerm_monitor_metric_alert.this["postgres-availability"].severity == 0
    error_message = "Database down must be a Sev 0 alert."
  }

  assert {
    condition     = length(azurerm_monitor_activity_log_alert.resource_health[0].scopes) == 4
    error_message = "Resource Health should cover every monitored resource."
  }

  assert {
    condition     = length(azurerm_monitor_alert_prometheus_rule_group.this[0].rule) == 5
    error_message = "Expected the Kubernetes Prometheus rule set."
  }

  assert {
    condition     = azurerm_consumption_budget_subscription.this[0].amount == 3000 && azurerm_consumption_budget_subscription.this[0].time_grain == "Monthly"
    error_message = "Expected a monthly subscription budget."
  }
}

run "rejects_no_receivers" {
  command = plan

  variables {
    action_group = { short_name = "platform" }
  }

  expect_failures = [var.action_group]
}

run "rejects_mid_month_budget" {
  command = plan

  variables {
    budget = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
      amount          = 3000
      start_date      = "2026-10-15T00:00:00Z"
    }
  }

  expect_failures = [var.budget]
}
