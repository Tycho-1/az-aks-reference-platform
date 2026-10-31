# Module templates

## versions.tf

```hcl
terraform {
  required_version = ">= 1.11.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
  }
}
```

Add `time = { source = "hashicorp/time", version = ">= 0.12, < 1.0" }` when the module waits for RBAC.

## variables.tf (standard tail)

```hcl
variable "private_endpoint" {
  description = "Private endpoint for the resource. Set `location` when the subnet's VNet is in another region."
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
    location            = optional(string)
  })
  default = null
}

variable "log_analytics_workspace" {
  description = "Send logs and metrics to Log Analytics. Null disables diagnostics."
  type = object({
    id = string
  })
  default = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
```

## main.tf (diagnostics)

```hcl
resource "azurerm_monitor_diagnostic_setting" "this" {
  count = var.log_analytics_workspace != null ? 1 : 0

  name                           = "diag-${var.name}"
  target_resource_id             = azurerm_<type>.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
```

## tests/<name>.tftest.hcl

```hcl
mock_provider "azurerm" {}

variables {
  name                = "<prefix>-test-weu"
  resource_group_name = "rg-test"
  location            = "westeurope"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = !azurerm_<type>.this.public_network_access_enabled
    error_message = "Public network access must be disabled by default."
  }
}

run "rejects_invalid_<input>" {
  command = plan

  variables {
    <input> = "<invalid>"
  }

  expect_failures = [var.<input>]
}
```
