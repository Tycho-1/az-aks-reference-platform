# Keycloak Microsoft (Entra ID) identity provider module

Lets users sign in to a Keycloak realm with their Entra ID account. Keycloak brokers to a single
tenant through an app registration, which [`entra-app-registration`](../../../entra-app-registration)
can create.

## What you get by default

| Area | Default |
|------|---------|
| Tenant | Single tenant: `tenant_id` must be a GUID; `common` and `organizations` are rejected |
| Email trust | `trust_email = false`. The Entra ID `email` claim isn't guaranteed to be verified, and trusting it allows account takeover through account linking ("nOAuth") |
| Sync | `IMPORT`: attributes are copied on first login |
| Mappers | Optional; every config value has a default, so a mapper with only a key is valid |

## Usage

```hcl
module "entra_id" {
  source = "../../modules/keycloak/identity-providers/microsoft"

  realm_id      = keycloak_realm.this.id
  tenant_id     = var.entra_tenant_id
  client_id     = module.keycloak_app.client_id
  client_secret = var.entra_client_secret

  attribute_mappers = {
    firstName = { json_field = "givenName" }
    lastName  = { json_field = "surname" }
  }
}
```

Register `https://<keycloak>/realms/<realm>/broker/microsoft/endpoint` as the redirect URI of the
app registration.

## Notes

- **Upgrading.** Resource addresses changed to `.this`; `moved` blocks migrate existing state.
  `trust_email` now defaults to `false`. The `mappers` output (which referenced a resource that
  doesn't exist) is replaced by `mapper_ids`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| attribute\_mappers | Mappers from Microsoft Graph user fields to Keycloak user attributes, keyed by mapper name. `json_field` and `user_attribute` default to the key. | ```map(object({ json_field = optional(string) user_attribute = optional(string) sync_mode = optional(string, "INHERIT") mapper_type = optional(string, "microsoft-user-attribute-mapper") extra_config = optional(map(string), {}) }))``` | `{}` | no |
| client\_id | Application (client) ID of the Entra ID app registration (see modules/entra-app-registration). | `string` | n/a | yes |
| client\_secret | Client secret of the Entra ID app registration. Pass it from a secret store, not a literal. | `string` | n/a | yes |
| default\_scopes | Scopes requested from Entra ID. | `string` | `"openid profile email"` | no |
| enabled | Whether users can sign in with this provider. | `bool` | `true` | no |
| first\_broker\_login\_flow\_alias | Authentication flow that runs the first time a user signs in through this provider. | `string` | `"first broker login"` | no |
| hide\_on\_login\_page | Hide the provider button on the login page (e.g. when it's only used through kc\_idp\_hint). | `bool` | `false` | no |
| realm\_id | Realm name (the `id` of a `keycloak_realm` resource). | `string` | n/a | yes |
| sync\_mode | How user attributes are updated on login: IMPORT (first login only), FORCE (every login) or LEGACY. | `string` | `"IMPORT"` | no |
| tenant\_id | Entra ID tenant ID. Only accounts of this tenant can sign in; multi-tenant endpoints (common, organizations) are rejected. | `string` | n/a | yes |
| trust\_email | Mark imported email addresses as verified. The Entra ID `email` claim is not guaranteed to be verified, so trusting it enables account takeover through account linking ("nOAuth"). | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| mapper\_ids | Attribute mapper IDs keyed by mapper name. |
| provider\_alias | Alias of the identity provider, used in redirect URIs and `kc_idp_hint`. |
| provider\_id | Terraform ID of the identity provider. |
<!-- END_TF_DOCS -->
