mock_provider "keycloak" {}

variables {
  realm_id      = "platform"
  client_id     = "1234567890-abc.apps.googleusercontent.com"
  client_secret = "test-secret"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = !keycloak_oidc_google_identity_provider.this.trust_email
    error_message = "Emails must not be trusted by default."
  }

  assert {
    condition     = keycloak_oidc_google_identity_provider.this.sync_mode == "IMPORT"
    error_message = "Unexpected default sync mode."
  }
}

run "workspace_domain_and_mappers" {
  command = plan

  variables {
    hosted_domain = "example.com"
    attribute_mappers = {
      firstName = { json_field = "given_name" }
      lastName  = { json_field = "family_name", sync_mode = "FORCE" }
    }
  }

  assert {
    condition     = keycloak_oidc_google_identity_provider.this.hosted_domain == "example.com"
    error_message = "hosted_domain must restrict sign-in to the Workspace domain."
  }

  assert {
    condition = keycloak_custom_identity_provider_mapper.this["firstName"].extra_config == tomap({
      syncMode      = "INHERIT"
      jsonField     = "given_name"
      userAttribute = "firstName"
    })
    error_message = "Mapper defaults must fill in every config value."
  }

  assert {
    condition     = keycloak_custom_identity_provider_mapper.this["lastName"].extra_config["syncMode"] == "FORCE"
    error_message = "Mapper sync_mode override is ignored."
  }
}

run "rejects_bad_hosted_domain" {
  command = plan

  variables {
    hosted_domain = "https://example.com"
  }

  expect_failures = [var.hosted_domain]
}

run "rejects_bad_mapper_sync_mode" {
  command = plan

  variables {
    attribute_mappers = { email = { sync_mode = "ALWAYS" } }
  }

  expect_failures = [var.attribute_mappers]
}
