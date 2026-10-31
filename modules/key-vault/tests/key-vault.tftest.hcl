mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
      object_id = "00000000-0000-0000-0000-000000000002"
    }
  }
}

mock_provider "time" {}

variables {
  name                = "kv-test-weu-abcd"
  resource_group_name = "rg-test"
  location            = "westeurope"

  keys = {
    aks-disk = {}
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "Purge protection and RBAC authorization must always be enabled."
  }

  assert {
    condition     = !azurerm_key_vault.this.public_network_access_enabled
    error_message = "Public network access must be disabled when no IP ranges are allowed."
  }

  assert {
    condition     = azurerm_key_vault_key.this["aks-disk"].key_type == "RSA-HSM" && azurerm_key_vault_key.this["aks-disk"].expiration_date == null
    error_message = "Keys default to HSM-backed and must not expire."
  }

  assert {
    condition     = azurerm_key_vault_key.this["aks-disk"].rotation_policy[0].automatic[0].time_after_creation == "P365D"
    error_message = "Keys must rotate automatically."
  }

  assert {
    condition     = length(azurerm_role_assignment.deployer) == 1
    error_message = "The deployer needs Crypto Officer to manage keys."
  }
}

run "allowed_ips_enable_public_access" {
  command = plan

  variables {
    allowed_ip_ranges = ["203.0.113.10/32"]
  }

  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled && azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "Allowed IPs should open the public endpoint with a default-deny firewall."
  }
}

run "rejects_long_name" {
  command = plan

  variables {
    name = "kv-this-name-is-far-too-long"
  }

  expect_failures = [var.name]
}

run "rejects_unsupported_key" {
  command = plan

  variables {
    keys = {
      bad = { key_type = "EC-HSM" }
    }
  }

  expect_failures = [var.keys]
}
