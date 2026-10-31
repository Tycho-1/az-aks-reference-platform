# Keycloak groups module

Groups with one level of subgroups, attributes, and realm and client role assignments. Grant
access through group membership rather than per-user role mappings, and map upstream identity
provider groups onto these groups.

## What you get by default

| Area | Behaviour |
|------|-----------|
| Roles | Referenced by name: `realm_roles = ["..."]`, `client_roles = { <client_id> = ["..."] }`. Each group gets a single role assignment that covers both |
| Assignment mode | Additive (`exhaustive = false`): roles granted outside Terraform are left alone. Set `exhaustive = true` to make Terraform the only source of role assignments |
| Attributes | `default_attributes` on every group and subgroup, overridden per group |

## Usage

```hcl
module "groups" {
  source = "../../modules/keycloak/groups"

  realm_id           = keycloak_realm.this.id
  default_attributes = { managed_by = "terraform" }
  exhaustive         = true

  groups = {
    platform = {
      name         = "platform"
      description  = "Platform team"
      client_roles = { sample-web = ["admin"] }
      subgroups = {
        oncall = { name = "oncall", realm_roles = ["incident-responder"] }
      }
    }
  }

  depends_on = [module.roles] # the roles are created in the same configuration
}
```

The `group_ids` output is keyed by logical name (`platform`, `platform:oncall`), for use in
identity provider group mappers.

## Notes

- **Ordering.** Roles and clients are looked up by name at plan time. If they are created in the
  same configuration, add `depends_on` on the module call.
- **Upgrading.** Realm and client roles used to be assigned by separate resources, which removed
  each other's roles with `exhaustive = true`. They are now one `keycloak_group_roles` per group;
  `moved` blocks migrate the former realm-role resources. Removing the former client-role resources
  can drop client roles for one apply; the next plan restores them. The `path` input was removed
  (Keycloak computes it), the `group_paths`, `subgroup_paths` and `group_roles` outputs were
  replaced by `groups` and `group_ids`, and `description` is now applied.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| default\_attributes | Attributes applied to every group and subgroup; per-group attributes take precedence. | `map(string)` | `{}` | no |
| exhaustive | Manage the full role set of each group: roles assigned outside Terraform are removed. False only adds the listed roles. | `bool` | `false` | no |
| groups | Groups keyed by a static logical name, with one optional level of subgroups. Roles are referenced by name: `realm_roles` lists realm role names, `client_roles` maps a client ID (the OAuth `client_id`) to role names. `parent_id` nests a group under an existing group. | ```map(object({ name = string description = optional(string) parent_id = optional(string) attributes = optional(map(string), {}) realm_roles = optional(list(string), []) client_roles = optional(map(list(string)), {}) subgroups = optional(map(object({ name = string description = optional(string) attributes = optional(map(string), {}) realm_roles = optional(list(string), []) client_roles = optional(map(list(string)), {}) })), {}) }))``` | `{}` | no |
| realm\_id | Realm name (the `id` of a `keycloak_realm` resource). | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| group\_ids | Group IDs keyed by logical name; subgroups use `<group>:<subgroup>`. Useful for identity provider group mappers. |
| groups | Groups keyed by logical name, with `id`, `name`, `path` and their `subgroups` (same shape, keyed by subgroup name). |
<!-- END_TF_DOCS -->
