# Keycloak roles module

Realm roles and client roles, including composite roles that bundle other roles (for example an
`admin` role that includes `viewer` and `editor`).

## What you get by default

| Area | Behaviour |
|------|-----------|
| Keys | Roles are keyed by static logical names; `composite_roles` references those keys |
| Composites | One level: a composite can include non-composite roles of the same realm or client. Validation rejects unknown keys, nested composites and cross-client references |
| Clients | Client roles are keyed by the OAuth `client_id`; the module looks up the client's internal ID |

## Usage

```hcl
module "roles" {
  source = "../../modules/keycloak/roles"

  realm_id = keycloak_realm.this.id

  realm_roles = {
    incident_responder = { name = "incident-responder", description = "Can acknowledge incidents" }
  }

  client_roles = {
    sample-web = {
      viewer = { name = "viewer" }
      editor = { name = "editor" }
      admin  = { name = "admin", composite_roles = ["viewer", "editor"] }
    }
  }

  depends_on = [module.web_client] # the client is created in the same configuration
}
```

## Notes

- **Ordering.** Clients are looked up by `client_id` at plan time. If the client is created in the
  same configuration, add `depends_on` on the module call.
- **Why two tiers.** A composite role references the IDs of its member roles, and a resource can't
  reference its own instances. The module creates non-composite roles first
  (`keycloak_role.realm_roles`, `keycloak_role.client_roles`), then composites
  (`*_composites`).
- **Upgrading.** Earlier versions created every composite role twice, which Keycloak rejects with
  a conflict. If an existing state has a composite role under `keycloak_role.realm_roles["<key>"]`,
  move it before applying: `terraform state mv 'module.roles.keycloak_role.realm_roles["admin"]' 'module.roles.keycloak_role.realm_role_composites["admin"]'`.
  The `realm_role_composites` and `client_role_composites` outputs were folded into `realm_roles`
  and `client_roles`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| client\_roles | Client roles keyed by client ID (the OAuth `client_id`), then by a static logical role name. `composite_roles` lists keys of non-composite roles of the same client. | ```map(map(object({ name = string description = optional(string) composite_roles = optional(list(string), []) attributes = optional(map(string), {}) })))``` | `{}` | no |
| realm\_id | Realm name (the `id` of a `keycloak_realm` resource). | `string` | n/a | yes |
| realm\_roles | Realm roles keyed by a static logical name. `composite_roles` lists keys of other roles in this map; a composite can only include roles that are not composites themselves. | ```map(object({ name = string description = optional(string) composite_roles = optional(list(string), []) attributes = optional(map(string), {}) }))``` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| client\_roles | Client roles keyed by client ID, then by logical role name, with `id` and `name`. |
| realm\_roles | Realm roles keyed by logical name, with `id` and `name`. |
<!-- END_TF_DOCS -->
