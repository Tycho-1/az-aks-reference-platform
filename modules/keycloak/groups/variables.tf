variable "realm_id" {
  description = "Realm name (the `id` of a `keycloak_realm` resource)."
  type        = string

  validation {
    condition     = length(var.realm_id) > 0
    error_message = "realm_id must not be empty."
  }
}

variable "groups" {
  description = <<-EOT
    Groups keyed by a static logical name, with one optional level of subgroups. Roles are
    referenced by name: `realm_roles` lists realm role names, `client_roles` maps a client ID
    (the OAuth `client_id`) to role names. `parent_id` nests a group under an existing group.
  EOT
  type = map(object({
    name         = string
    description  = optional(string)
    parent_id    = optional(string)
    attributes   = optional(map(string), {})
    realm_roles  = optional(list(string), [])
    client_roles = optional(map(list(string)), {})
    subgroups = optional(map(object({
      name         = string
      description  = optional(string)
      attributes   = optional(map(string), {})
      realm_roles  = optional(list(string), [])
      client_roles = optional(map(list(string)), {})
    })), {})
  }))
  default = {}

  validation {
    condition = alltrue(flatten([
      for group in values(var.groups) : concat(
        [length(group.name) > 0],
        [for subgroup in values(group.subgroups) : length(subgroup.name) > 0],
      )
    ]))
    error_message = "Group and subgroup names must not be empty."
  }
}

variable "default_attributes" {
  description = "Attributes applied to every group and subgroup; per-group attributes take precedence."
  type        = map(string)
  default     = {}
}

variable "exhaustive" {
  description = "Manage the full role set of each group: roles assigned outside Terraform are removed. False only adds the listed roles."
  type        = bool
  default     = false
}
