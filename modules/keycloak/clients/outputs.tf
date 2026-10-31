output "id" {
  description = "Internal Keycloak ID (UUID) of the client. Other resources (roles, scopes, mappers) reference this."
  value       = keycloak_openid_client.this.id
}

output "client_id" {
  description = "Client identifier used in OAuth requests."
  value       = keycloak_openid_client.this.client_id
}

output "client_secret" {
  description = "Secret of a CONFIDENTIAL client; null for other access types."
  value       = var.access_type == "CONFIDENTIAL" ? keycloak_openid_client.this.client_secret : null
  sensitive   = true
}

output "service_account_user_id" {
  description = "ID of the service account user when service accounts are enabled, for assigning roles to it."
  value       = var.service_accounts_enabled ? keycloak_openid_client.this.service_account_user_id : null
}
