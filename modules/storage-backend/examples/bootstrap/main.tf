# Bootstraps remote state for the platform. Run once with local state, then
# optionally migrate this stack's own state into the account (`terraform init -migrate-state`).

terraform {
  required_version = ">= 1.11"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
  }
}

provider "azurerm" {
  features {}
  storage_use_azuread = true
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "storage_account_name" {
  description = "Globally unique, e.g. sttfstateplatform<random>."
  type        = string
}

variable "operator_ip_ranges" {
  description = "Public IPs/CIDRs (your workstation, CI egress) allowed to reach the state account."
  type        = list(string)
  default     = []
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate-mgmt-weu"
  location = var.location
  tags     = local.tags
}

locals {
  tags = {
    workload   = "terraform-state"
    managed_by = "terraform"
  }
}

module "state" {
  source = "../../"

  storage_account_name = var.storage_account_name
  resource_group_name  = azurerm_resource_group.tfstate.name
  location             = azurerm_resource_group.tfstate.location

  container_names = ["platform-dev", "platform-prod"]

  network_access = {
    ip_rules = var.operator_ip_ranges
  }

  state_contributors = {
    deployer = {
      principal_id   = data.azurerm_client_config.current.object_id
      principal_type = "User"
    }
  }

  tags = local.tags
}

output "backend_configs" {
  value = module.state.backend_configs
}
