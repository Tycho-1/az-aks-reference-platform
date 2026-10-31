mock_provider "keycloak" {}

variables {
  realm_id            = "platform"
  client_id           = "sample-web"
  access_type         = "CONFIDENTIAL"
  valid_redirect_uris = ["https://app.example.com/callback"]
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = keycloak_openid_client.this.pkce_code_challenge_method == "S256"
    error_message = "PKCE (S256) must be required by default."
  }

  assert {
    condition = (
      !keycloak_openid_client.this.implicit_flow_enabled &&
      !keycloak_openid_client.this.direct_access_grants_enabled &&
      !keycloak_openid_client.this.service_accounts_enabled
    )
    error_message = "Implicit, password and client credentials grants must be off by default."
  }

  assert {
    condition     = !keycloak_openid_client.this.full_scope_allowed
    error_message = "Tokens must be limited to mapped scopes by default."
  }

  assert {
    condition     = keycloak_openid_client.this.web_origins == toset(["+"])
    error_message = "CORS must default to the redirect URI origins."
  }

  assert {
    condition     = keycloak_openid_client.this.name == "sample-web"
    error_message = "name should default to client_id."
  }
}

run "public_spa" {
  command = plan

  variables {
    access_type         = "PUBLIC"
    valid_redirect_uris = ["https://app.example.com/*", "http://localhost:5173/*"]
  }

  assert {
    condition     = keycloak_openid_client.this.client_authenticator_type == null
    error_message = "Public clients have no authenticator."
  }

  assert {
    condition     = keycloak_openid_client.this.pkce_code_challenge_method == "S256"
    error_message = "Public clients must use PKCE."
  }
}

run "bearer_only_api_has_no_flows" {
  command = plan

  variables {
    access_type         = "BEARER-ONLY"
    valid_redirect_uris = []
  }

  assert {
    condition = (
      !keycloak_openid_client.this.standard_flow_enabled &&
      keycloak_openid_client.this.pkce_code_challenge_method == ""
    )
    error_message = "Bearer-only clients must not enable any flow."
  }
}

run "service_account" {
  command = plan

  variables {
    service_accounts_enabled = true
    standard_flow_enabled    = false
    valid_redirect_uris      = []
  }

  assert {
    condition     = keycloak_openid_client.this.service_accounts_enabled
    error_message = "service_accounts_enabled should enable the client credentials grant."
  }
}

run "rejects_wildcard_redirect" {
  command = plan

  variables {
    valid_redirect_uris = ["*"]
  }

  expect_failures = [var.valid_redirect_uris]
}

run "rejects_plain_http_redirect" {
  command = plan

  variables {
    valid_redirect_uris = ["http://app.example.com/callback"]
  }

  expect_failures = [var.valid_redirect_uris]
}

run "rejects_wildcard_web_origin" {
  command = plan

  variables {
    web_origins = ["*"]
  }

  expect_failures = [var.web_origins]
}

run "rejects_unknown_access_type" {
  command = plan

  variables {
    access_type = "confidential"
  }

  expect_failures = [var.access_type]
}

run "standard_flow_needs_redirect_uris" {
  command = plan

  variables {
    valid_redirect_uris = []
  }

  expect_failures = [keycloak_openid_client.this]
}

run "public_client_rejects_service_accounts" {
  command = plan

  variables {
    access_type              = "PUBLIC"
    service_accounts_enabled = true
  }

  expect_failures = [keycloak_openid_client.this]
}

run "public_client_rejects_secret" {
  command = plan

  variables {
    access_type   = "PUBLIC"
    client_secret = "not-for-public-clients"
  }

  expect_failures = [keycloak_openid_client.this]
}
