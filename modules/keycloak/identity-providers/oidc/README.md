# Keycloak OIDC identity provider module

Brokers sign-in to any OpenID Connect provider (a partner's IdP, Okta, Auth0, another Keycloak)
that has no dedicated Keycloak integration.

## What you get by default

| Area | Default |
|------|---------|
| Token validation | `issuer` is required and checked; signatures are validated against `jwks_url` |
| PKCE | `S256` on the authorization code flow to the upstream provider |
| Endpoints | Every URL must use `https://` |
| Email trust | `trust_email = false` |
| Tokens | Upstream tokens aren't stored (`store_token = false`) |
| Mappers | `oidc-user-attribute-idp-mapper` from a claim to a user attribute; `claim` and `user_attribute` default to the key |

## Usage

Take the URLs from the provider's discovery document
(`<issuer>/.well-known/openid-configuration`):

```hcl
module "partner_sso" {
  source = "../../modules/keycloak/identity-providers/oidc"

  realm_id      = keycloak_realm.this.id
  alias         = "partner-sso"
  display_name  = "Partner SSO"
  client_id     = "keycloak-broker"
  client_secret = var.partner_client_secret

  issuer            = "https://idp.partner.example"
  authorization_url = "https://idp.partner.example/oauth2/authorize"
  token_url         = "https://idp.partner.example/oauth2/token"
  jwks_url          = "https://idp.partner.example/oauth2/jwks"
  user_info_url     = "https://idp.partner.example/oauth2/userinfo"

  attribute_mappers = {
    email     = {}
    firstName = { claim = "given_name" }
    lastName  = { claim = "family_name" }
  }
}
```

## Notes

- **PKCE** is set through `extra_config` (`pkceEnabled`, `pkceMethod`), because the provider has
  no dedicated arguments for it. Values in `extra_config` take precedence.
- **Upgrading.** The resource address changed to `keycloak_oidc_identity_provider.this`; a `moved`
  block migrates existing state. `issuer` is now required, `use_jwks_url` was removed (the provider
  always uses the JWKS URL), and `attribute_mappers` now creates mappers.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| alias | Unique alias of the provider in the realm. Appears in the broker redirect URI (`/realms/<realm>/broker/<alias>/endpoint`). | `string` | n/a | yes |
| attribute\_mappers | Mappers from token claims to Keycloak user attributes, keyed by mapper name. `claim` and `user_attribute` default to the key. | ```map(object({ claim = optional(string) user_attribute = optional(string) sync_mode = optional(string, "INHERIT") mapper_type = optional(string, "oidc-user-attribute-idp-mapper") extra_config = optional(map(string), {}) }))``` | `{}` | no |
| authorization\_url | Authorization endpoint (from the provider's discovery document). | `string` | n/a | yes |
| client\_id | Client ID registered at the upstream provider. | `string` | n/a | yes |
| client\_secret | Client secret registered at the upstream provider. Pass it from a secret store, not a literal. | `string` | n/a | yes |
| default\_scopes | Scopes requested from the upstream provider. | `string` | `"openid profile email"` | no |
| display\_name | Button label on the login page. Defaults to the alias. | `string` | `null` | no |
| enabled | Whether users can sign in with this provider. | `bool` | `true` | no |
| extra\_config | Additional provider config (e.g. `prompt`). Takes precedence over the PKCE settings this module sets. | `map(string)` | `{}` | no |
| first\_broker\_login\_flow\_alias | Authentication flow that runs the first time a user signs in through this provider. | `string` | `"first broker login"` | no |
| hide\_on\_login\_page | Hide the provider button on the login page (e.g. when it's only used through kc\_idp\_hint). | `bool` | `false` | no |
| issuer | Issuer URL of the upstream provider. Keycloak rejects tokens whose `iss` claim doesn't match. | `string` | n/a | yes |
| jwks\_url | JWKS endpoint used to validate token signatures. Required while validate\_signature is true. | `string` | `null` | no |
| link\_only | Only allow linking to existing Keycloak accounts; no sign-in or registration. | `bool` | `false` | no |
| logout\_url | End-session endpoint, called when the user logs out of Keycloak. | `string` | `null` | no |
| pkce\_enabled | Use PKCE (S256) on the authorization code flow to the upstream provider. | `bool` | `true` | no |
| realm\_id | Realm name (the `id` of a `keycloak_realm` resource). | `string` | n/a | yes |
| store\_token | Store the upstream tokens so applications can retrieve them from Keycloak. | `bool` | `false` | no |
| sync\_mode | How user attributes are updated on login: IMPORT (first login only), FORCE (every login) or LEGACY. | `string` | `"IMPORT"` | no |
| token\_url | Token endpoint. | `string` | n/a | yes |
| trust\_email | Mark imported email addresses as verified. Enable only if the upstream provider verifies email addresses. | `bool` | `false` | no |
| user\_info\_url | UserInfo endpoint. Null uses the ID token claims only. | `string` | `null` | no |
| validate\_signature | Validate the signature of tokens from the upstream provider against jwks\_url. | `bool` | `true` | no |

## Outputs

| Name | Description |
|------|-------------|
| mapper\_ids | Attribute mapper IDs keyed by mapper name. |
| provider\_alias | Alias of the identity provider, used in redirect URIs and `kc_idp_hint`. |
| provider\_id | Terraform ID of the identity provider. |
<!-- END_TF_DOCS -->
