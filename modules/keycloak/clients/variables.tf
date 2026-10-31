variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "client_id" {
  description = "Client identifier used in OAuth requests (`client_id`). Unique within the realm."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._:-]+$", var.client_id))
    error_message = "client_id may only contain letters, digits, '.', '_', ':' and '-'."
  }
}

variable "name" {
  description = "Display name in the Keycloak console. Defaults to client_id."
  type        = string
  default     = null
}

variable "description" {
  description = "Description of the client."
  type        = string
  default     = null
}

variable "access_type" {
  description = "CONFIDENTIAL for server-side apps that can keep a secret, PUBLIC for browser and native apps (PKCE only), BEARER-ONLY for APIs that only validate tokens."
  type        = string

  validation {
    condition     = contains(["CONFIDENTIAL", "PUBLIC", "BEARER-ONLY"], var.access_type)
    error_message = "access_type must be CONFIDENTIAL, PUBLIC or BEARER-ONLY."
  }
}

variable "client_authenticator_type" {
  description = "How a CONFIDENTIAL client authenticates. `client-jwt` (signed JWT, no shared secret) is stronger than `client-secret`."
  type        = string
  default     = "client-secret"

  validation {
    condition     = contains(["client-secret", "client-jwt", "client-secret-jwt", "client-x509"], var.client_authenticator_type)
    error_message = "client_authenticator_type must be client-secret, client-jwt, client-secret-jwt or client-x509."
  }
}

variable "client_secret" {
  description = "Secret for a CONFIDENTIAL client. Null lets Keycloak generate one, which is exposed by the `client_secret` output."
  type        = string
  default     = null
  sensitive   = true
}

variable "root_url" {
  description = "Root URL of the application, prepended to relative redirect URIs."
  type        = string
  default     = null
}

variable "admin_url" {
  description = "URL Keycloak calls for back-channel admin requests (e.g. logout)."
  type        = string
  default     = null
}

variable "valid_redirect_uris" {
  description = "Allowed redirect URIs. HTTPS only, except `http://localhost` and `http://127.0.0.1` for local development. A trailing `/*` is allowed; a bare `*` is not."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for uri in var.valid_redirect_uris :
      uri != "*" && can(regex("^(https://|http://localhost[:/]|http://127\\.0\\.0\\.1[:/]|/)", uri))
    ])
    error_message = "Redirect URIs must use https:// (or http://localhost / http://127.0.0.1) or be relative to root_url, and must not be '*'."
  }
}

variable "web_origins" {
  description = "Allowed CORS origins. `+` (the default) allows the origins of `valid_redirect_uris` and nothing else."
  type        = list(string)
  default     = ["+"]

  validation {
    condition     = !contains(var.web_origins, "*")
    error_message = "web_origins must not contain '*'. Use '+' to allow the origins of the redirect URIs."
  }
}

variable "standard_flow_enabled" {
  description = "Enable the authorization code flow. Ignored for BEARER-ONLY clients."
  type        = bool
  default     = true
}

variable "pkce_enabled" {
  description = "Require PKCE (S256) on the authorization code flow. Recommended for every client type by OAuth 2.1."
  type        = bool
  default     = true
}

variable "service_accounts_enabled" {
  description = "Enable the client credentials grant (machine-to-machine). CONFIDENTIAL clients only."
  type        = bool
  default     = false
}

variable "direct_access_grants_enabled" {
  description = "Enable the resource owner password grant. Deprecated by OAuth 2.1; leave off unless a legacy client needs it."
  type        = bool
  default     = false
}

variable "full_scope_allowed" {
  description = "Put every role of the user into the client's tokens. False limits tokens to roles mapped through client scopes (least privilege)."
  type        = bool
  default     = false
}

variable "login_theme" {
  description = "Login theme for this client. Null uses the realm theme."
  type        = string
  default     = null
}
