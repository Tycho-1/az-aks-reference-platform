# Alerting module

Platform alerting: one action group plus the recommended alerts for each monitored component,
based on the
[Azure Monitor recommended alert rules](https://learn.microsoft.com/azure/azure-monitor/alerts/alerts-overview)
and the [AKS recommended Prometheus alerts](https://learn.microsoft.com/azure/aks/monitor-aks#alerts).

Pass only the components you run; each one adds its own set of rules.

## What you get

| Component | Alerts (name: condition, severity) |
|-----------|------------------------------------|
| `aks` | `aks-node-cpu` > 90% (2), `aks-node-memory` > 90% (2), `aks-node-disk` > 90% (2), `aks-unschedulable-pods` > 0 for 30 min (3) |
| `prometheus` | `KubeNodeNotReady` (2), `KubePodCrashLooping` (3), `KubePodNotReady` (3), `KubeDeploymentReplicasMismatch` (3), `KubePersistentVolumeFillingUp` > 85% (2) |
| `postgres` | `postgres-availability` down (**0**), `postgres-storage` > 80% (1), `postgres-cpu` > 80% (2), `postgres-memory` > 90% (2) |
| `firewall` | `firewall-health` < 90% (1), `firewall-snat` > 80% (2) |
| `key_vaults` | `kv-<name>-availability` < 99% (1), `kv-<name>-saturation` > 75% (2) |
| `resource_health_enabled` | Any monitored resource becomes Degraded or Unavailable |
| `service_health` | Azure incidents, maintenance, security advisories and required actions in your regions |
| `budget` | Monthly subscription budget: actual spend at 80% and 100%, forecast at 100% |

Severity 0 is critical and 4 is verbose. Route Sev 0-1 to paging and the rest to a channel,
using separate action groups or a webhook into your incident tool.

## Usage

```hcl
module "alerting" {
  source = "../../modules/alerting"

  name_prefix         = "platform-prod-weu"
  resource_group_name = azurerm_resource_group.ops.name
  location            = "westeurope"

  action_group = {
    short_name      = "platformops"
    email_receivers = { oncall = "platform-oncall@example.com" }
  }

  aks        = { cluster_id = module.aks.id }
  prometheus = { monitor_workspace_id = azurerm_monitor_workspace.this.id, cluster_name = module.aks.name }
  postgres   = { server_id = module.postgres.id }
  firewall   = { id = module.hub.firewall_id }
  key_vaults = { primary = module.key_vault.id }

  alert_overrides = {
    postgres-cpu        = { threshold = 70 }
    KubePodNotReady     = { severity = 4 }
    aks-unschedulable-pods = { enabled = false }
  }
}
```

## Notes

- Thresholds are starting points. Tune them after a few weeks of real traffic with
  `alert_overrides` rather than editing the module.
- Every alert auto-resolves when the condition clears and uses the common alert schema, so
  webhook consumers (PagerDuty, Opsgenie, Teams, Slack) get one payload format.
- The Prometheus rules use only metrics in managed Prometheus' default ingestion profile. Custom
  application alerts belong in your own rule groups, delivered with the workloads.
- The subscription budget needs Cost Management permissions on the subscription, and
  `start_date` can't be in a past month when the budget is created.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| action\_group | Action group notified by every alert. Receivers are keyed by a static name. | ```object({ short_name = string email_receivers = optional(map(string), {}) webhook_receivers = optional(map(string), {}) })``` | n/a | yes |
| aks | AKS cluster to monitor with platform metric alerts. | ```object({ cluster_id = string })``` | `null` | no |
| alert\_overrides | Per-alert adjustments keyed by alert name (e.g. `postgres-cpu`, `aks-node-memory`), to tune thresholds, severity or disable a rule without forking the module. | ```map(object({ threshold = optional(number) severity = optional(number) enabled = optional(bool) }))``` | `{}` | no |
| budget | Monthly subscription budget. `start_date` must be the first day of a month (e.g. 2026-10-01T00:00:00Z). Notifications go to the action group and `contact_emails`. | ```object({ subscription_id = string amount = number start_date = string contact_emails = optional(list(string), []) actual_thresholds = optional(list(number), [80, 100]) forecast_threshold = optional(number, 100) })``` | `null` | no |
| firewall | Azure Firewall to monitor. | ```object({ id = string })``` | `null` | no |
| key\_vaults | Key Vaults to monitor, keyed by a static logical name. | `map(string)` | `{}` | no |
| location | Region for regional alert resources (Prometheus rule groups); use the Azure Monitor workspace region. | `string` | n/a | yes |
| name\_prefix | Prefix for alert resource names, e.g. platform-prod-weu. | `string` | n/a | yes |
| postgres | PostgreSQL Flexible Server to monitor. | ```object({ server_id = string })``` | `null` | no |
| prometheus | Managed Prometheus alert rules for the cluster (node readiness, crash loops, replicas, volumes). | ```object({ monitor_workspace_id = string cluster_name = string })``` | `null` | no |
| resource\_group\_name | Name of an existing resource group for the alert resources. | `string` | n/a | yes |
| resource\_health\_enabled | Alert when a monitored resource becomes Degraded or Unavailable (Resource Health). | `bool` | `true` | no |
| service\_health | Alert on Azure service incidents, maintenance and security advisories in these regions. | ```object({ subscription_id = string locations = list(string) })``` | `null` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| action\_group\_id | ID of the action group, for attaching further alerts. |
| metric\_alert\_ids | Metric alert IDs keyed by alert name. |
| prometheus\_rule\_group\_id | ID of the Kubernetes Prometheus rule group, if created. |
<!-- END_TF_DOCS -->
