variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "realm_roles" {
  description = <<-EOT
    Realm roles keyed by a static logical name. `composite_roles` lists keys of other roles in this
    map; a composite can only include roles that are not composites themselves.
  EOT
  type = map(object({
    name            = string
    description     = optional(string)
    composite_roles = optional(list(string), [])
    attributes      = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for role in values(var.realm_roles) : length(role.name) > 0])
    error_message = "Role names must not be empty."
  }

  validation {
    condition = alltrue(flatten([
      for role in values(var.realm_roles) : [
        for key in role.composite_roles :
        try(length(var.realm_roles[key].composite_roles) == 0, false)
      ]
    ]))
    error_message = "composite_roles must reference keys of non-composite roles in realm_roles."
  }
}

variable "client_roles" {
  description = <<-EOT
    Client roles keyed by client ID (the OAuth `client_id`), then by a static logical role name.
    `composite_roles` lists keys of non-composite roles of the same client.
  EOT
  type = map(map(object({
    name            = string
    description     = optional(string)
    composite_roles = optional(list(string), [])
    attributes      = optional(map(string), {})
  })))
  default = {}

  validation {
    condition = alltrue(flatten([
      for client, roles in var.client_roles : [
        for role in values(roles) : length(client) > 0 && length(role.name) > 0
      ]
    ]))
    error_message = "Client IDs and role names must not be empty."
  }

  validation {
    condition = alltrue(flatten([
      for roles in values(var.client_roles) : [
        for role in values(roles) : [
          for key in role.composite_roles :
          try(length(roles[key].composite_roles) == 0, false)
        ]
      ]
    ]))
    error_message = "composite_roles must reference keys of non-composite roles of the same client."
  }
}
