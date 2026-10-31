mock_provider "azurerm" {}

mock_provider "time" {}

variables {
  name                = "crtestweuabcd"
  resource_group_name = "rg-test"
  location            = "westeurope"

  private_endpoint = {
    subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-pe"
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-hub/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io"
  }
}

run "private_premium_defaults" {
  command = plan

  assert {
    condition     = !azurerm_container_registry.this.admin_enabled && !azurerm_container_registry.this.anonymous_pull_enabled
    error_message = "Admin user and anonymous pull must be disabled."
  }

  assert {
    condition     = !azurerm_container_registry.this.public_network_access_enabled && !azurerm_container_registry.this.export_policy_enabled
    error_message = "A private Premium registry must block public access and image export."
  }

  assert {
    condition     = azurerm_container_registry.this.zone_redundancy_enabled
    error_message = "Premium registries should be zone redundant."
  }

  assert {
    condition     = length(azurerm_private_endpoint.this) == 1
    error_message = "A private endpoint is expected."
  }
}

run "customer_managed_key" {
  command = plan

  variables {
    customer_managed_key = {
      key_vault_id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-test"
      key_vault_key_id = "https://kv-test.vault.azure.net/keys/acr"
    }
  }

  assert {
    condition     = azurerm_role_assignment.cmk[0].role_definition_name == "Key Vault Crypto Service Encryption User"
    error_message = "The registry identity needs crypto access to the key."
  }

  assert {
    condition     = azurerm_container_registry.this.encryption[0].key_vault_key_id == "https://kv-test.vault.azure.net/keys/acr"
    error_message = "The registry should be encrypted with the supplied key."
  }
}

run "standard_sku_rejects_private_endpoint" {
  command = plan

  variables {
    sku = "Standard"
  }

  expect_failures = [azurerm_container_registry.this]
}

run "unreachable_registry_rejected" {
  command = plan

  variables {
    private_endpoint = null
  }

  expect_failures = [azurerm_container_registry.this]
}
