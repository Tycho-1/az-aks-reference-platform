terraform {
  # Write-only arguments need Terraform 1.11. 1.11.0 cannot encode a sensitive
  # write-only value such as administrator_password_wo (fixed in 1.11.1).
  required_version = ">= 1.11.1"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0, < 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.12, < 1.0"
    }
  }
}
