# Keycloak Google identity provider module

Lets users sign in to a Keycloak realm with a Google account, optionally restricted to one Google
Workspace domain.

## What you get by default

| Area | Default |
|------|---------|
| Accounts | Any Google account, unless `hosted_domain` restricts sign-in to a Workspace domain (checked against the `hd` claim). Set it for workforce realms |
| Email trust | `trust_email = false`; enable it explicitly if you rely on Google-verified emails for account linking |
| Sync | `IMPORT`: attributes are copied on first login |
| Mappers | Optional; every config value has a default, so a mapper with only a key is valid |

## Usage

```hcl
module "google" {
  source = "../../modules/keycloak/identity-providers/google"

  realm_id      = keycloak_realm.this.id
  client_id     = var.google_client_id
  client_secret = var.google_client_secret
  hosted_domain = "example.com"

  attribute_mappers = {
    firstName = { json_field = "given_name" }
    lastName  = { json_field = "family_name" }
  }
}
```

Register `https://<keycloak>/realms/<realm>/broker/google/endpoint` as an authorized redirect URI
of the OAuth client in the Google Cloud console.

## Notes

- **Upgrading.** Resource addresses changed to `.this`; `moved` blocks migrate existing state.
  `trust_email` now defaults to `false`. The `mappers` output (which referenced a resource that
  doesn't exist) is replaced by `mapper_ids`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| attribute\_mappers | Mappers from Google user info fields to Keycloak user attributes, keyed by mapper name. `json_field` and `user_attribute` default to the key. | ```map(object({ json_field = optional(string) user_attribute = optional(string) sync_mode = optional(string, "INHERIT") mapper_type = optional(string, "google-user-attribute-mapper") extra_config = optional(map(string), {}) }))``` | `{}` | no |
| client\_id | OAuth client ID from the Google Cloud console. | `string` | n/a | yes |
| client\_secret | OAuth client secret from the Google Cloud console. Pass it from a secret store, not a literal. | `string` | n/a | yes |
| default\_scopes | Scopes requested from Google. | `string` | `"openid profile email"` | no |
| enabled | Whether users can sign in with this provider. | `bool` | `true` | no |
| first\_broker\_login\_flow\_alias | Authentication flow that runs the first time a user signs in through this provider. | `string` | `"first broker login"` | no |
| hide\_on\_login\_page | Hide the provider button on the login page (e.g. when it's only used through kc\_idp\_hint). | `bool` | `false` | no |
| hosted\_domain | Only accept accounts of this Google Workspace domain (checked against the `hd` claim). Null accepts any Google account. | `string` | `null` | no |
| realm\_id | Realm name (the `id` of a `keycloak_realm` resource). | `string` | n/a | yes |
| sync\_mode | How user attributes are updated on login: IMPORT (first login only), FORCE (every login) or LEGACY. | `string` | `"IMPORT"` | no |
| trust\_email | Mark imported email addresses as verified. Enable only if every account that can sign in has a verified address you trust for account linking. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| mapper\_ids | Attribute mapper IDs keyed by mapper name. |
| provider\_alias | Alias of the identity provider, used in redirect URIs and `kc_idp_hint`. |
| provider\_id | Terraform ID of the identity provider. |
<!-- END_TF_DOCS -->
