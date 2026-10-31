output "action_group_id" {
  description = "ID of the action group, for attaching further alerts."
  value       = azurerm_monitor_action_group.this.id
}

output "metric_alert_ids" {
  description = "Metric alert IDs keyed by alert name."
  value       = { for k, v in azurerm_monitor_metric_alert.this : k => v.id }
}

output "prometheus_rule_group_id" {
  description = "ID of the Kubernetes Prometheus rule group, if created."
  value       = try(azurerm_monitor_alert_prometheus_rule_group.this[0].id, null)
}
