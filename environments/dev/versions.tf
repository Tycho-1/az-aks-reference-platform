terraform {
  required_version = ">= 1.11.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
  }

  # Partial configuration: terraform init -backend-config=backend.hcl
  backend "azurerm" {} # to comment when needed to run locally
}

provider "azurerm" {
  # Subscription comes from ARM_SUBSCRIPTION_ID; authenticate with Azure CLI locally or OIDC in CI.
  features {}
  storage_use_azuread = true
}
