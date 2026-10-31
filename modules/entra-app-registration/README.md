# Entra ID application registration module

Creates an Entra ID (Azure AD) app registration and its service principal for an OIDC confidential
client. Typical uses are an identity broker such as Keycloak, an internal web app, or an API.

## What changed compared to a typical hand-rolled app registration

- **No provider blocks inside the module.** The caller configures `azuread`, so the module can be
  used with `for_each`, and credentials are never module inputs.
- **No hard-coded Graph GUIDs.** Permissions are given by name (`openid`, `User.Read`, ...) and
  resolved from the Microsoft Graph service principal.
- **Stable, generated app role IDs** instead of copy-pasted UUIDs.
- **Secrets rotate automatically** (`time_rotating`) with a grace period, instead of a fixed
  end date that silently expires. Federated credentials are supported so you can avoid secrets
  entirely.
- **Assignment required by default**: only users and groups assigned to the app can sign in.
- **Implicit flow disabled**: use the authorization code flow.

## Usage

```hcl
module "sso_app" {
  source = "../../modules/entra-app-registration"

  display_name  = "platform-sso-prod"
  redirect_uris = ["https://sso.example.com/realms/platform/broker/entra/endpoint"]

  app_roles = {
    admin  = { display_name = "Admin", description = "Full administrative access" }
    reader = { display_name = "Reader", description = "Read-only access" }
  }

  app_role_assignments = {
    platform_admins = { app_role = "admin", principal_object_id = "<group-object-id>" }
  }

  client_secret = { rotation_days = 90 }
}
```

Store `client_secret` in Key Vault (for example with `azurerm_key_vault_secret`) and let the
consumer read it from there. Don't pass it through outputs across stacks.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `display_name` | App name | required |
| `sign_in_audience` | Tenant scope | `AzureADMyOrg` |
| `owners` | Owner object IDs | caller |
| `redirect_uris`, `logout_url` | Web platform settings (HTTPS enforced) | `[]`, `null` |
| `graph_delegated_permissions` | Graph scopes by name | `openid, profile, email, User.Read` |
| `optional_claims`, `group_membership_claims` | Token contents | `email`, `upn` in ID token |
| `app_roles` | Roles keyed by value | `{}` |
| `app_role_assignments` | Role → principal assignments | `{}` |
| `assignment_required` | Require assignment to sign in | `true` |
| `client_secret` | `{ rotation_days, grace_days }` or `null` | `null` |
| `federated_credentials` | Workload identity federation | `{}` |

## Outputs

`client_id`, `application_object_id`, `service_principal_object_id`, `tenant_id`, `app_role_ids`,
`oidc` (issuer, discovery, authorize, token endpoints), `client_secret` (sensitive),
`client_secret_expires_at`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| app\_role\_assignments | Assign users, groups or service principals to app roles, keyed by a static name. Prefer groups. | ```map(object({ app_role = string principal_object_id = string }))``` | `{}` | no |
| app\_roles | App roles keyed by role value (the value emitted in the `roles` claim). IDs are generated and kept stable. | ```map(object({ display_name = string description = string allowed_member_types = optional(list(string), ["User"]) enabled = optional(bool, true) }))``` | `{}` | no |
| assignment\_required | Only principals assigned to the app (directly or via group) can sign in. | `bool` | `true` | no |
| client\_secret | Client secret with scheduled rotation. Prefer `federated_credentials` (workload identity federation) wherever the client supports it, so no secret exists at all. Null creates no secret. | ```object({ rotation_days = optional(number, 90) grace_days = optional(number, 30) })``` | `null` | no |
| description | Description of the application. | `string` | `null` | no |
| display\_name | Display name of the application registration. | `string` | n/a | yes |
| federated\_credentials | Workload identity federation credentials keyed by name, e.g. a GitHub Actions environment (issuer https://token.actions.githubusercontent.com) or an AKS service account (issuer = cluster OIDC issuer URL, subject system:serviceaccount:<ns>:<sa>). | ```map(object({ issuer = string subject = string audiences = optional(list(string), ["api://AzureADTokenExchange"]) description = optional(string) }))``` | `{}` | no |
| graph\_delegated\_permissions | Microsoft Graph delegated permissions by name. Resolved to IDs at plan time, so no GUIDs are hard-coded. | `list(string)` | ```[ "openid", "profile", "email", "User.Read" ]``` | no |
| group\_membership\_claims | Group claims to emit in tokens, e.g. ["SecurityGroup"] or ["ApplicationGroup"]. | `list(string)` | `[]` | no |
| logout\_url | Front-channel logout URL. | `string` | `null` | no |
| optional\_claims | Optional claims for ID and access tokens. | ```object({ id_token = optional(list(object({ name = string essential = optional(bool, false) additional_properties = optional(list(string), []) })), []) access_token = optional(list(object({ name = string essential = optional(bool, false) additional_properties = optional(list(string), []) })), []) })``` | ```{ "id_token": [ { "name": "email" }, { "name": "upn" } ] }``` | no |
| owners | Object IDs of application owners. Defaults to the identity running Terraform. | `list(string)` | `null` | no |
| redirect\_uris | Web redirect URIs (e.g. an OIDC broker callback such as https://sso.example.com/realms/<realm>/broker/entra/endpoint). | `list(string)` | `[]` | no |
| sign\_in\_audience | Who can sign in. AzureADMyOrg restricts the app to the home tenant. | `string` | `"AzureADMyOrg"` | no |

## Outputs

| Name | Description |
|------|-------------|
| app\_role\_ids | App role IDs keyed by role value. |
| application\_object\_id | Object ID of the application registration. |
| client\_id | Application (client) ID. |
| client\_secret | Current client secret value, if a secret is managed. Store it in Key Vault rather than passing it around. |
| client\_secret\_expires\_at | Expiry of the current client secret. |
| oidc | OIDC endpoints for configuring a relying party or identity broker. |
| service\_principal\_object\_id | Object ID of the enterprise application (service principal). |
| tenant\_id | Tenant ID of the application. |
<!-- END_TF_DOCS -->
