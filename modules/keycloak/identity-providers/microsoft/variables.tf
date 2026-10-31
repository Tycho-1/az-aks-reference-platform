variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "client_id" {
  description = "Application (client) ID of the Entra ID app registration (see modules/entra-app-registration)."
  type        = string
}

variable "client_secret" {
  description = "Client secret of the Entra ID app registration. Pass it from a secret store, not a literal."
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Entra ID tenant ID. Only accounts of this tenant can sign in; multi-tenant endpoints (common, organizations) are rejected."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a tenant GUID."
  }
}

variable "enabled" {
  description = "Whether users can sign in with this provider."
  type        = bool
  default     = true
}

variable "default_scopes" {
  description = "Scopes requested from Entra ID."
  type        = string
  default     = "openid profile email"
}

variable "trust_email" {
  description = "Mark imported email addresses as verified. The Entra ID `email` claim is not guaranteed to be verified, so trusting it enables account takeover through account linking (\"nOAuth\")."
  type        = bool
  default     = false
}

variable "sync_mode" {
  description = "How user attributes are updated on login: IMPORT (first login only), FORCE (every login) or LEGACY."
  type        = string
  default     = "IMPORT"

  validation {
    condition     = contains(["IMPORT", "FORCE", "LEGACY"], var.sync_mode)
    error_message = "sync_mode must be IMPORT, FORCE or LEGACY."
  }
}

variable "hide_on_login_page" {
  description = "Hide the provider button on the login page (e.g. when it's only used through kc_idp_hint)."
  type        = bool
  default     = false
}

variable "first_broker_login_flow_alias" {
  description = "Authentication flow that runs the first time a user signs in through this provider."
  type        = string
  default     = "first broker login"
}

variable "attribute_mappers" {
  description = "Mappers from Microsoft Graph user fields to Keycloak user attributes, keyed by mapper name. `json_field` and `user_attribute` default to the key."
  type = map(object({
    json_field     = optional(string)
    user_attribute = optional(string)
    sync_mode      = optional(string, "INHERIT")
    mapper_type    = optional(string, "microsoft-user-attribute-mapper")
    extra_config   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for m in values(var.attribute_mappers) : contains(["INHERIT", "IMPORT", "FORCE", "LEGACY"], m.sync_mode)])
    error_message = "Mapper sync_mode must be INHERIT, IMPORT, FORCE or LEGACY."
  }
}
