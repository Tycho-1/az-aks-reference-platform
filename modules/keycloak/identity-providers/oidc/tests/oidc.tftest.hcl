mock_provider "keycloak" {}

variables {
  realm_id          = "platform"
  alias             = "partner-sso"
  client_id         = "keycloak-broker"
  client_secret     = "test-secret"
  issuer            = "https://idp.example.com"
  authorization_url = "https://idp.example.com/authorize"
  token_url         = "https://idp.example.com/token"
  jwks_url          = "https://idp.example.com/.well-known/jwks.json"
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = keycloak_oidc_identity_provider.this.validate_signature
    error_message = "Signatures must be validated by default."
  }

  assert {
    condition     = keycloak_oidc_identity_provider.this.extra_config["pkceEnabled"] == "true" && keycloak_oidc_identity_provider.this.extra_config["pkceMethod"] == "S256"
    error_message = "PKCE (S256) must be enabled by default."
  }

  assert {
    condition     = !keycloak_oidc_identity_provider.this.trust_email && !keycloak_oidc_identity_provider.this.store_token
    error_message = "Emails must not be trusted and tokens not stored by default."
  }

  assert {
    condition     = keycloak_oidc_identity_provider.this.display_name == "partner-sso"
    error_message = "display_name should default to the alias."
  }
}

run "mappers_and_extra_config" {
  command = plan

  variables {
    extra_config = { prompt = "login" }
    attribute_mappers = {
      email     = {}
      firstName = { claim = "given_name" }
    }
  }

  assert {
    condition     = keycloak_oidc_identity_provider.this.extra_config["prompt"] == "login"
    error_message = "extra_config must be passed through."
  }

  assert {
    condition = keycloak_custom_identity_provider_mapper.this["firstName"].extra_config == tomap({
      syncMode         = "INHERIT"
      claim            = "given_name"
      "user.attribute" = "firstName"
    })
    error_message = "Mapper defaults must fill in every config value."
  }
}

run "signature_validation_needs_jwks" {
  command = plan

  variables {
    jwks_url = null
  }

  expect_failures = [keycloak_oidc_identity_provider.this]
}

run "rejects_http_endpoint" {
  command = plan

  variables {
    token_url = "http://idp.example.com/token"
  }

  expect_failures = [var.token_url]
}

run "rejects_bad_alias" {
  command = plan

  variables {
    alias = "Partner SSO"
  }

  expect_failures = [var.alias]
}
