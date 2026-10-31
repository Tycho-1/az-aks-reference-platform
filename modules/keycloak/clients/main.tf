locals {
  bearer_only   = var.access_type == "BEARER-ONLY"
  standard_flow = !local.bearer_only && var.standard_flow_enabled
}

resource "keycloak_openid_client" "this" {
  realm_id    = var.realm_id
  client_id   = var.client_id
  name        = coalesce(var.name, var.client_id)
  description = var.description
  enabled     = true

  access_type               = var.access_type
  client_authenticator_type = var.access_type == "CONFIDENTIAL" ? var.client_authenticator_type : null
  client_secret             = var.access_type == "CONFIDENTIAL" ? var.client_secret : null

  # The provider rejects any flow on a bearer-only client.
  standard_flow_enabled        = local.standard_flow
  implicit_flow_enabled        = false
  direct_access_grants_enabled = !local.bearer_only && var.direct_access_grants_enabled
  service_accounts_enabled     = !local.bearer_only && var.service_accounts_enabled
  pkce_code_challenge_method   = local.standard_flow && var.pkce_enabled ? "S256" : ""
  full_scope_allowed           = var.full_scope_allowed

  root_url            = var.root_url
  admin_url           = var.admin_url
  valid_redirect_uris = local.standard_flow ? var.valid_redirect_uris : null
  web_origins         = local.standard_flow ? var.web_origins : null
  login_theme         = var.login_theme

  lifecycle {
    precondition {
      condition     = !local.standard_flow || length(var.valid_redirect_uris) > 0
      error_message = "valid_redirect_uris must contain at least one URI when the standard flow is enabled."
    }

    precondition {
      condition     = var.access_type == "CONFIDENTIAL" || !var.service_accounts_enabled
      error_message = "service_accounts_enabled requires access_type CONFIDENTIAL."
    }

    precondition {
      condition     = var.access_type == "CONFIDENTIAL" || var.client_secret == null
      error_message = "client_secret can only be set for CONFIDENTIAL clients."
    }
  }
}

moved {
  from = keycloak_openid_client.client
  to   = keycloak_openid_client.this
}
