# Plans the dev environment against mocked providers to catch wiring errors
# (unknown values in for_each/count, cross-module references) without Azure access.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000001"
    }
  }
}

# terraform test also loads a local terraform.tfvars; pin every value the assertions depend on.
variables {
  location                        = "westeurope"
  location_short                  = "weu"
  aks_admin_group_object_ids      = ["11111111-1111-1111-1111-111111111111"]
  api_server_authorized_ip_ranges = ["203.0.113.10/32"]
}

run "dev_plan" {
  command = plan

  assert {
    condition     = module.aks.name == "aks-platform-dev-weu"
    error_message = "Unexpected cluster name."
  }

  assert {
    condition     = length(module.postgres) == 0
    error_message = "Dev should default to AKS-only without postgres_enabled."
  }
}

run "dev_with_postgres" {
  command = plan

  variables {
    postgres_enabled = true
    postgres_admin_group = {
      object_id    = "22222222-2222-2222-2222-222222222222"
      display_name = "sg-platform-postgres-admins"
    }
  }

  assert {
    condition     = length(module.postgres) == 1
    error_message = "postgres_enabled should create the server module."
  }
}

run "prod_plan" {
  command = plan

  variables {
    environment      = "prod"
    postgres_enabled = true
    postgres_admin_group = {
      object_id    = "22222222-2222-2222-2222-222222222222"
      display_name = "sg-platform-postgres-admins"
    }
  }

  assert {
    condition     = module.aks.name == "aks-platform-prod-weu"
    error_message = "Unexpected cluster name."
  }
}
