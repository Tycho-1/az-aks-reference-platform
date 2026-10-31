variable "display_name" {
  description = "Display name of the application registration."
  type        = string
}

variable "description" {
  description = "Description of the application."
  type        = string
  default     = null
}

variable "sign_in_audience" {
  description = "Who can sign in. AzureADMyOrg restricts the app to the home tenant."
  type        = string
  default     = "AzureADMyOrg"

  validation {
    condition     = contains(["AzureADMyOrg", "AzureADMultipleOrgs", "AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount"], var.sign_in_audience)
    error_message = "Invalid sign_in_audience."
  }
}

variable "owners" {
  description = "Object IDs of application owners. Defaults to the identity running Terraform."
  type        = list(string)
  default     = null
}

variable "redirect_uris" {
  description = "Web redirect URIs (e.g. an OIDC broker callback such as https://sso.example.com/realms/<realm>/broker/entra/endpoint)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for uri in var.redirect_uris : startswith(uri, "https://") || startswith(uri, "http://localhost")])
    error_message = "Redirect URIs must use https:// (http://localhost is allowed for development)."
  }
}

variable "logout_url" {
  description = "Front-channel logout URL."
  type        = string
  default     = null
}

variable "group_membership_claims" {
  description = "Group claims to emit in tokens, e.g. [\"SecurityGroup\"] or [\"ApplicationGroup\"]."
  type        = list(string)
  default     = []
}

variable "optional_claims" {
  description = "Optional claims for ID and access tokens."
  type = object({
    id_token = optional(list(object({
      name                  = string
      essential             = optional(bool, false)
      additional_properties = optional(list(string), [])
    })), [])
    access_token = optional(list(object({
      name                  = string
      essential             = optional(bool, false)
      additional_properties = optional(list(string), [])
    })), [])
  })
  default = {
    id_token = [
      { name = "email" },
      { name = "upn" },
    ]
  }
}

variable "graph_delegated_permissions" {
  description = "Microsoft Graph delegated permissions by name. Resolved to IDs at plan time, so no GUIDs are hard-coded."
  type        = list(string)
  default     = ["openid", "profile", "email", "User.Read"]
}

variable "app_roles" {
  description = "App roles keyed by role value (the value emitted in the `roles` claim). IDs are generated and kept stable."
  type = map(object({
    display_name         = string
    description          = string
    allowed_member_types = optional(list(string), ["User"])
    enabled              = optional(bool, true)
  }))
  default = {}
}

variable "app_role_assignments" {
  description = "Assign users, groups or service principals to app roles, keyed by a static name. Prefer groups."
  type = map(object({
    app_role            = string
    principal_object_id = string
  }))
  default = {}

  validation {
    condition     = alltrue([for a in values(var.app_role_assignments) : contains(keys(var.app_roles), a.app_role)])
    error_message = "Every app_role_assignments[*].app_role must reference a key of app_roles."
  }
}

variable "assignment_required" {
  description = "Only principals assigned to the app (directly or via group) can sign in."
  type        = bool
  default     = true
}

variable "client_secret" {
  description = <<-EOT
    Client secret with scheduled rotation. Prefer `federated_credentials` (workload identity
    federation) wherever the client supports it, so no secret exists at all. Null creates no secret.
  EOT
  type = object({
    rotation_days = optional(number, 90)
    grace_days    = optional(number, 30)
  })
  default = null
}

variable "federated_credentials" {
  description = <<-EOT
    Workload identity federation credentials keyed by name, e.g. a GitHub Actions environment
    (issuer https://token.actions.githubusercontent.com) or an AKS service account
    (issuer = cluster OIDC issuer URL, subject system:serviceaccount:<ns>:<sa>).
  EOT
  type = map(object({
    issuer      = string
    subject     = string
    audiences   = optional(list(string), ["api://AzureADTokenExchange"])
    description = optional(string)
  }))
  default = {}
}
