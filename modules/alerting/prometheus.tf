locals {
  # Based on the Azure Monitor recommended Prometheus alert rules for AKS. The expressions only
  # use metrics in managed Prometheus' default (minimal) ingestion profile.
  prometheus_rules = {
    KubeNodeNotReady = {
      expression  = "kube_node_status_condition{job=\"kube-state-metrics\",condition=\"Ready\",status=\"true\"} == 0"
      for         = "PT15M"
      severity    = 2
      description = "Node {{ $labels.node }} has been NotReady for more than 15 minutes."
    }
    KubePodCrashLooping = {
      expression  = "max_over_time(kube_pod_container_status_waiting_reason{job=\"kube-state-metrics\",reason=\"CrashLoopBackOff\"}[5m]) >= 1"
      for         = "PT15M"
      severity    = 3
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} ({{ $labels.container }}) is in CrashLoopBackOff."
    }
    KubePodNotReady = {
      expression  = "sum by (cluster, namespace, pod) (max by (cluster, namespace, pod) (kube_pod_status_phase{job=\"kube-state-metrics\",phase=~\"Pending|Unknown\"})) > 0"
      for         = "PT15M"
      severity    = 3
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} has been Pending or Unknown for more than 15 minutes."
    }
    KubeDeploymentReplicasMismatch = {
      expression  = "kube_deployment_spec_replicas{job=\"kube-state-metrics\"} != kube_deployment_status_replicas_available{job=\"kube-state-metrics\"}"
      for         = "PT15M"
      severity    = 3
      description = "Deployment {{ $labels.namespace }}/{{ $labels.deployment }} has not matched its desired replicas for 15 minutes."
    }
    KubePersistentVolumeFillingUp = {
      expression  = "kubelet_volume_stats_used_bytes{job=\"kubelet\"} / kubelet_volume_stats_capacity_bytes{job=\"kubelet\"} > 0.85"
      for         = "PT15M"
      severity    = 2
      description = "PersistentVolumeClaim {{ $labels.namespace }}/{{ $labels.persistentvolumeclaim }} is more than 85% full."
    }
  }
}

resource "azurerm_monitor_alert_prometheus_rule_group" "this" {
  count = var.prometheus != null ? 1 : 0

  name                = "prom-${var.name_prefix}-kubernetes"
  resource_group_name = var.resource_group_name
  location            = var.location
  cluster_name        = var.prometheus.cluster_name
  scopes              = [var.prometheus.monitor_workspace_id]
  description         = "Kubernetes workload and node health alerts."
  interval            = "PT1M"
  rule_group_enabled  = true
  tags                = var.tags

  dynamic "rule" {
    for_each = local.prometheus_rules
    content {
      alert       = rule.key
      expression  = rule.value.expression
      for         = rule.value.for
      severity    = try(coalesce(var.alert_overrides[rule.key].severity, rule.value.severity), rule.value.severity)
      enabled     = try(coalesce(var.alert_overrides[rule.key].enabled, true), true)
      annotations = { description = rule.value.description }

      action {
        action_group_id = azurerm_monitor_action_group.this.id
      }

      alert_resolution {
        auto_resolved   = true
        time_to_resolve = "PT10M"
      }
    }
  }
}
