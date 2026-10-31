output "provider_id" {
  description = "Terraform ID of the identity provider."
  value       = keycloak_oidc_google_identity_provider.this.id
}

output "provider_alias" {
  description = "Alias of the identity provider, used in redirect URIs and `kc_idp_hint`."
  value       = keycloak_oidc_google_identity_provider.this.alias
}

output "mapper_ids" {
  description = "Attribute mapper IDs keyed by mapper name."
  value       = { for key, mapper in keycloak_custom_identity_provider_mapper.this : key => mapper.id }
}
