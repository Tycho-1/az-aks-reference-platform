variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "client_id" {
  description = "OAuth client ID from the Google Cloud console."
  type        = string
}

variable "client_secret" {
  description = "OAuth client secret from the Google Cloud console. Pass it from a secret store, not a literal."
  type        = string
  sensitive   = true
}

variable "hosted_domain" {
  description = "Only accept accounts of this Google Workspace domain (checked against the `hd` claim). Null accepts any Google account."
  type        = string
  default     = null

  validation {
    condition     = var.hosted_domain == null || can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", var.hosted_domain))
    error_message = "hosted_domain must be a domain name such as example.com."
  }
}

variable "enabled" {
  description = "Whether users can sign in with this provider."
  type        = bool
  default     = true
}

variable "default_scopes" {
  description = "Scopes requested from Google."
  type        = string
  default     = "openid profile email"
}

variable "trust_email" {
  description = "Mark imported email addresses as verified. Enable only if every account that can sign in has a verified address you trust for account linking."
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
  description = "Mappers from Google user info fields to Keycloak user attributes, keyed by mapper name. `json_field` and `user_attribute` default to the key."
  type = map(object({
    json_field     = optional(string)
    user_attribute = optional(string)
    sync_mode      = optional(string, "INHERIT")
    mapper_type    = optional(string, "google-user-attribute-mapper")
    extra_config   = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for m in values(var.attribute_mappers) : contains(["INHERIT", "IMPORT", "FORCE", "LEGACY"], m.sync_mode)])
    error_message = "Mapper sync_mode must be INHERIT, IMPORT, FORCE or LEGACY."
  }
}
