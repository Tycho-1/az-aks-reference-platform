mock_provider "keycloak" {}

variables {
  realm_id      = "platform"
  client_id     = "33333333-3333-3333-3333-333333333333"
  client_secret = "test-secret"
  tenant_id     = "00000000-0000-0000-0000-000000000001"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = !keycloak_oidc_microsoft_identity_provider.this.trust_email
    error_message = "Entra ID emails must not be trusted by default (nOAuth)."
  }

  assert {
    condition     = keycloak_oidc_microsoft_identity_provider.this.tenant_id == "00000000-0000-0000-0000-000000000001"
    error_message = "Sign-in must be limited to the configured tenant."
  }
}

run "mappers" {
  command = plan

  variables {
    attribute_mappers = {
      jobTitle = {}
    }
  }

  assert {
    condition = keycloak_custom_identity_provider_mapper.this["jobTitle"].extra_config == tomap({
      syncMode      = "INHERIT"
      jsonField     = "jobTitle"
      userAttribute = "jobTitle"
    })
    error_message = "Mapper defaults must fill in every config value."
  }

  assert {
    condition     = keycloak_custom_identity_provider_mapper.this["jobTitle"].identity_provider_mapper == "microsoft-user-attribute-mapper"
    error_message = "Unexpected default mapper type."
  }
}

run "rejects_multi_tenant_endpoint" {
  command = plan

  variables {
    tenant_id = "common"
  }

  expect_failures = [var.tenant_id]
}
