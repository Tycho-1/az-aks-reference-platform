# Plans the composed example against a mocked provider to catch wiring errors between the
# Keycloak modules without a Keycloak server.

mock_provider "keycloak" {}

variables {
  keycloak_client_secret = "test-secret"
  entra_tenant_id        = "00000000-0000-0000-0000-000000000001"
  entra_client_id        = "33333333-3333-3333-3333-333333333333"
  entra_client_secret    = "test-secret"
}

run "complete_plan" {
  command = plan

  assert {
    condition     = module.web_client.client_id == "sample-web"
    error_message = "Unexpected web client ID."
  }

  assert {
    condition     = toset(keys(module.groups.groups)) == toset(["platform", "readers"])
    error_message = "Unexpected groups."
  }
}
