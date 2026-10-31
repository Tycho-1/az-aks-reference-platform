resource "keycloak_oidc_google_identity_provider" "this" {
  realm   = var.realm_id
  enabled = var.enabled

  client_id     = var.client_id
  client_secret = var.client_secret
  hosted_domain = var.hosted_domain

  default_scopes = var.default_scopes
  trust_email    = var.trust_email
  sync_mode      = var.sync_mode

  hide_on_login_page            = var.hide_on_login_page
  first_broker_login_flow_alias = var.first_broker_login_flow_alias
}

resource "keycloak_custom_identity_provider_mapper" "this" {
  for_each = var.attribute_mappers

  realm                    = var.realm_id
  name                     = each.key
  identity_provider_alias  = keycloak_oidc_google_identity_provider.this.alias
  identity_provider_mapper = each.value.mapper_type

  extra_config = merge(
    {
      syncMode      = each.value.sync_mode
      jsonField     = coalesce(each.value.json_field, each.key)
      userAttribute = coalesce(each.value.user_attribute, each.key)
    },
    each.value.extra_config,
  )
}

moved {
  from = keycloak_oidc_google_identity_provider.google
  to   = keycloak_oidc_google_identity_provider.this
}

moved {
  from = keycloak_custom_identity_provider_mapper.google_mapper
  to   = keycloak_custom_identity_provider_mapper.this
}
