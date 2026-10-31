mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}

variables {
  name                = "psql-test-dev-weu"
  resource_group_name = "rg-test"
  location            = "westeurope"
  delegated_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-postgres"

  private_dns_zone = {
    virtual_network_ids = {
      hub = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-net/providers/Microsoft.Network/virtualNetworks/vnet-test"
    }
  }

  entra_administrator = {
    object_id      = "11111111-1111-1111-1111-111111111111"
    principal_name = "sg-postgres-admins"
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = !azurerm_postgresql_flexible_server.this.public_network_access_enabled
    error_message = "The server must not have a public endpoint."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.authentication[0].active_directory_auth_enabled && !azurerm_postgresql_flexible_server.this.authentication[0].password_auth_enabled
    error_message = "Entra-only authentication is the expected default."
  }

  assert {
    condition     = azurerm_postgresql_flexible_server.this.high_availability[0].mode == "ZoneRedundant"
    error_message = "Zone-redundant HA is the expected default."
  }

  assert {
    condition     = azurerm_private_dns_zone.this[0].name == "psql-test-dev-weu.private.postgres.database.azure.com"
    error_message = "The module should create a private DNS zone when none is supplied."
  }

  assert {
    condition     = length(azurerm_management_lock.this) == 1
    error_message = "A delete lock is expected by default."
  }
}

run "burstable_sku_rejects_ha" {
  command = plan

  variables {
    sku_name = "B_Standard_B2s"
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}

run "password_auth_needs_login" {
  command = plan

  variables {
    password_auth_enabled  = true
    administrator_password = "not-a-real-password-1!"
  }

  expect_failures = [azurerm_postgresql_flexible_server.this]
}
