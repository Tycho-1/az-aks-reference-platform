resource "keycloak_oidc_identity_provider" "this" {
  realm        = var.realm_id
  alias        = var.alias
  display_name = coalesce(var.display_name, var.alias)
  enabled      = var.enabled

  client_id     = var.client_id
  client_secret = var.client_secret

  issuer             = var.issuer
  authorization_url  = var.authorization_url
  token_url          = var.token_url
  jwks_url           = var.jwks_url
  user_info_url      = var.user_info_url
  logout_url         = var.logout_url
  validate_signature = var.validate_signature

  default_scopes = var.default_scopes
  trust_email    = var.trust_email
  store_token    = var.store_token
  link_only      = var.link_only
  sync_mode      = var.sync_mode

  hide_on_login_page            = var.hide_on_login_page
  first_broker_login_flow_alias = var.first_broker_login_flow_alias

  # The provider has no PKCE arguments; Keycloak reads them from the provider config map.
  extra_config = merge(
    var.pkce_enabled ? { pkceEnabled = "true", pkceMethod = "S256" } : { pkceEnabled = "false" },
    var.extra_config,
  )

  lifecycle {
    precondition {
      condition     = !var.validate_signature || var.jwks_url != null
      error_message = "jwks_url is required when validate_signature is true."
    }
  }
}

resource "keycloak_custom_identity_provider_mapper" "this" {
  for_each = var.attribute_mappers

  realm                    = var.realm_id
  name                     = each.key
  identity_provider_alias  = keycloak_oidc_identity_provider.this.alias
  identity_provider_mapper = each.value.mapper_type

  extra_config = merge(
    {
      syncMode         = each.value.sync_mode
      claim            = coalesce(each.value.claim, each.key)
      "user.attribute" = coalesce(each.value.user_attribute, each.key)
    },
    each.value.extra_config,
  )
}

moved {
  from = keycloak_oidc_identity_provider.oidc_idp
  to   = keycloak_oidc_identity_provider.this
}
