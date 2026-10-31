terraform {
  required_version = ">= 1.11.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6, < 4.0"
    }
  }

  # Partial configuration: terraform init -backend-config=backend.hcl
  backend "azurerm" {} # to comment the backend when needed to run locally
}

provider "azurerm" {
  # Subscription comes from ARM_SUBSCRIPTION_ID; authenticate with Azure CLI locally or OIDC in CI.
  features {
    key_vault {
      # Keys protect data at rest; never purge them as part of a destroy.
      purge_soft_deleted_keys_on_destroy = false
    }
  }
  storage_use_azuread = true
}
