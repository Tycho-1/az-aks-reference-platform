variable "name_prefix" {
  description = "Prefix for alert resource names, e.g. platform-prod-weu."
  type        = string
}

variable "resource_group_name" {
  description = "Name of an existing resource group for the alert resources."
  type        = string
}

variable "location" {
  description = "Region for regional alert resources (Prometheus rule groups); use the Azure Monitor workspace region."
  type        = string
}

variable "action_group" {
  description = "Action group notified by every alert. Receivers are keyed by a static name."
  type = object({
    short_name        = string
    email_receivers   = optional(map(string), {})
    webhook_receivers = optional(map(string), {})
  })

  validation {
    condition     = length(var.action_group.short_name) <= 12
    error_message = "action_group.short_name must be 12 characters or fewer."
  }

  validation {
    condition     = length(var.action_group.email_receivers) + length(var.action_group.webhook_receivers) > 0
    error_message = "Configure at least one email or webhook receiver, otherwise alerts reach no one."
  }
}

variable "aks" {
  description = "AKS cluster to monitor with platform metric alerts."
  type = object({
    cluster_id = string
  })
  default = null
}

variable "prometheus" {
  description = "Managed Prometheus alert rules for the cluster (node readiness, crash loops, replicas, volumes)."
  type = object({
    monitor_workspace_id = string
    cluster_name         = string
  })
  default = null
}

variable "postgres" {
  description = "PostgreSQL Flexible Server to monitor."
  type = object({
    server_id = string
  })
  default = null
}

variable "firewall" {
  description = "Azure Firewall to monitor."
  type = object({
    id = string
  })
  default = null
}

variable "key_vaults" {
  description = "Key Vaults to monitor, keyed by a static logical name."
  type        = map(string)
  default     = {}
}

variable "alert_overrides" {
  description = <<-EOT
    Per-alert adjustments keyed by alert name (e.g. `postgres-cpu`, `aks-node-memory`), to tune
    thresholds, severity or disable a rule without forking the module.
  EOT
  type = map(object({
    threshold = optional(number)
    severity  = optional(number)
    enabled   = optional(bool)
  }))
  default = {}
}

variable "service_health" {
  description = "Alert on Azure service incidents, maintenance and security advisories in these regions."
  type = object({
    subscription_id = string
    locations       = list(string)
  })
  default = null
}

variable "resource_health_enabled" {
  description = "Alert when a monitored resource becomes Degraded or Unavailable (Resource Health)."
  type        = bool
  default     = true
}

variable "budget" {
  description = <<-EOT
    Monthly subscription budget. `start_date` must be the first day of a month
    (e.g. 2026-10-01T00:00:00Z). Notifications go to the action group and `contact_emails`.
  EOT
  type = object({
    subscription_id    = string
    amount             = number
    start_date         = string
    contact_emails     = optional(list(string), [])
    actual_thresholds  = optional(list(number), [80, 100])
    forecast_threshold = optional(number, 100)
  })
  default = null

  validation {
    condition     = var.budget == null ? true : can(regex("^\\d{4}-\\d{2}-01T00:00:00Z$", var.budget.start_date))
    error_message = "budget.start_date must be the first day of a month, formatted YYYY-MM-01T00:00:00Z."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
