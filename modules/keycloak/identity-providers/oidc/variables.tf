variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "alias" {
  description = "Unique alias of the provider in the realm. Appears in the broker redirect URI (`/realms/<realm>/broker/<alias>/endpoint`)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.alias))
    error_message = "alias must be lowercase letters, digits and hyphens."
  }
}

variable "display_name" {
  description = "Button label on the login page. Defaults to the alias."
  type        = string
  default     = null
}

variable "enabled" {
  description = "Whether users can sign in with this provider."
  type        = bool
  default     = true
}

variable "client_id" {
  description = "Client ID registered at the upstream provider."
  type        = string
}

variable "client_secret" {
  description = "Client secret registered at the upstream provider. Pass it from a secret store, not a literal."
  type        = string
  sensitive   = true
}

variable "issuer" {
  description = "Issuer URL of the upstream provider. Keycloak rejects tokens whose `iss` claim doesn't match."
  type        = string

  validation {
    condition     = startswith(var.issuer, "https://")
    error_message = "issuer must be an https:// URL."
  }
}

variable "authorization_url" {
  description = "Authorization endpoint (from the provider's discovery document)."
  type        = string

  validation {
    condition     = startswith(var.authorization_url, "https://")
    error_message = "authorization_url must be an https:// URL."
  }
}

variable "token_url" {
  description = "Token endpoint."
  type        = string

  validation {
    condition     = startswith(var.token_url, "https://")
    error_message = "token_url must be an https:// URL."
  }
}

variable "jwks_url" {
  description = "JWKS endpoint used to validate token signatures. Required while validate_signature is true."
  type        = string
  default     = null

  validation {
    condition     = var.jwks_url == null || startswith(coalesce(var.jwks_url, "-"), "https://")
    error_message = "jwks_url must be an https:// URL."
  }
}

variable "user_info_url" {
  description = "UserInfo endpoint. Null uses the ID token claims only."
  type        = string
  default     = null

  validation {
    condition     = var.user_info_url == null || startswith(coalesce(var.user_info_url, "-"), "https://")
    error_message = "user_info_url must be an https:// URL."
  }
}

variable "logout_url" {
  description = "End-session endpoint, called when the user logs out of Keycloak."
  type        = string
  default     = null

  validation {
    condition     = var.logout_url == null || startswith(coalesce(var.logout_url, "-"), "https://")
    error_message = "logout_url must be an https:// URL."
  }
}

variable "validate_signature" {
  description = "Validate the signature of tokens from the upstream provider against jwks_url."
  type        = bool
  default     = true
}

variable "pkce_enabled" {
  description = "Use PKCE (S256) on the authorization code flow to the upstream provider."
  type        = bool
  default     = true
}

variable "default_scopes" {
  description = "Scopes requested from the upstream provider."
  type        = string
  default     = "openid profile email"
}

variable "trust_email" {
  description = "Mark imported email addresses as verified. Enable only if the upstream provider verifies email addresses."
  type        = bool
  default     = false
}

variable "store_token" {
  description = "Store the upstream tokens so applications can retrieve them from Keycloak."
  type        = bool
  default     = false
}

variable "link_only" {
  description = "Only allow linking to existing Keycloak accounts; no sign-in or registration."
  type        = bool
  default     = false
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

variable "sync_mode" {
  description = "How user attributes are updated on login: IMPORT (first login only), FORCE (every login) or LEGACY."
  type        = string
  default     = "IMPORT"

  validation {
    condition     = contains(["IMPORT", "FORCE", "LEGACY"], var.sync_mode)
    error_message = "sync_mode must be IMPORT, FORCE or LEGACY."
  }
}

variable "extra_config" {
  description = "Additional provider config (e.g. `prompt`). Takes precedence over the PKCE settings this module sets."
  type        = map(string)
  default     = {}
}

variable "attribute_mappers" {
  description = "Mappers from token claims to Keycloak user attributes, keyed by mapper name. `claim` and `user_attribute` default to the key."
  type = map(object({
    claim          = optional(string)
    user_attribute = optional(string)
    sync_mode      = optional(string, "INHERIT")
    mapper_type    = optional(string, "oidc-user-attribute-idp-mapper")
    extra_config   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for m in values(var.attribute_mappers) : contains(["INHERIT", "IMPORT", "FORCE", "LEGACY"], m.sync_mode)])
    error_message = "Mapper sync_mode must be INHERIT, IMPORT, FORCE or LEGACY."
  }
}
