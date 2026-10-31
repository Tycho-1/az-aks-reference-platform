mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id              = "/subscriptions/00000000-0000-0000-0000-000000000003"
      subscription_id = "00000000-0000-0000-0000-000000000003"
      tenant_id       = "00000000-0000-0000-0000-000000000001"
    }
  }
}

variables {
  github_repository        = "example-org/az-aks-reference-platform"
  state_storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000003/resourceGroups/rg-tfstate/providers/Microsoft.Storage/storageAccounts/sttfstate001"
}

run "least_privilege_identities" {
  command = plan

  assert {
    condition     = azurerm_federated_identity_credential.this["apply"].subject == "repo:example-org/az-aks-reference-platform:environment:production"
    error_message = "Apply must only trust the protected production environment."
  }

  assert {
    condition     = !contains([for ra in azurerm_role_assignment.this : ra.role_definition_name], "Owner")
    error_message = "No identity may be Owner."
  }

  assert {
    condition     = azurerm_role_assignment.this["plan-reader"].role_definition_name == "Reader" && !contains(keys(azurerm_role_assignment.this), "plan-contributor")
    error_message = "The plan identity must be read-only."
  }

  assert {
    condition     = strcontains(azurerm_role_assignment.apply_rbac_admin.condition, "8e3af657-a8ff-443c-a75c-2fe8c4bcb635")
    error_message = "The apply identity's RBAC administrator role must exclude Owner."
  }
}

run "rejects_bad_repository" {
  command = plan

  variables {
    github_repository = "not-a-repo"
  }

  expect_failures = [var.github_repository]
}
