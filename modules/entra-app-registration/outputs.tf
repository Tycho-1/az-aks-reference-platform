output "client_id" {
  description = "Application (client) ID."
  value       = azuread_application.this.client_id
}

output "application_object_id" {
  description = "Object ID of the application registration."
  value       = azuread_application.this.object_id
}

output "service_principal_object_id" {
  description = "Object ID of the enterprise application (service principal)."
  value       = azuread_service_principal.this.object_id
}

output "tenant_id" {
  description = "Tenant ID of the application."
  value       = data.azuread_client_config.current.tenant_id
}

output "app_role_ids" {
  description = "App role IDs keyed by role value."
  value       = { for k, v in random_uuid.app_role : k => v.result }
}

output "oidc" {
  description = "OIDC endpoints for configuring a relying party or identity broker."
  value = {
    issuer                 = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0"
    discovery_url          = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/v2.0/.well-known/openid-configuration"
    authorization_endpoint = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/authorize"
    token_endpoint         = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/oauth2/v2.0/token"
  }
}

output "client_secret" {
  description = "Current client secret value, if a secret is managed. Store it in Key Vault rather than passing it around."
  value       = try(azuread_application_password.this[0].value, null)
  sensitive   = true
}

output "client_secret_expires_at" {
  description = "Expiry of the current client secret."
  value       = try(azuread_application_password.this[0].end_date, null)
}
