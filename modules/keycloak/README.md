# Keycloak modules

Modules for the realm configuration of a Keycloak server: OIDC clients, roles, groups and
identity brokering to Entra ID, Google or any OIDC provider. They use the
[`keycloak/keycloak`](https://registry.terraform.io/providers/keycloak/keycloak/latest/docs)
provider and are independent of the Azure platform. Keycloak itself runs wherever you host it
(for example on the AKS cluster through GitOps).

| Module | Purpose |
|--------|---------|
| [`clients`](clients) | OIDC client with PKCE, no implicit or password grant, least-privilege token scope |
| [`roles`](roles) | Realm and client roles, including composite roles |
| [`groups`](groups) | Groups and subgroups with realm and client role assignments |
| [`identity-providers/microsoft`](identity-providers/microsoft) | Single-tenant Entra ID sign-in |
| [`identity-providers/google`](identity-providers/google) | Google sign-in, optionally limited to a Workspace domain |
| [`identity-providers/oidc`](identity-providers/oidc) | Any OIDC provider, with issuer and signature validation and PKCE |

[`examples/complete`](examples/complete) composes all of them: a realm, a confidential web
client and a bearer-only API, roles, groups with role assignments, and Entra ID sign-in.

## Conventions

The modules follow the same rules as the Azure modules in this repository:

- **No provider blocks.** The caller configures the provider. Authenticate Terraform as a
  service-account client (client credentials grant) with only the `realm-management` roles it
  needs, not as the `admin` user with a password.
- **Secure by default.** PKCE is required, implicit and password grants are off, tokens carry only
  mapped roles, emails from external providers aren't trusted, and redirect URIs and endpoints must
  use HTTPS. Relaxing a default is an explicit input.
- **Realms by ID.** Every module takes `realm_id`: the `id` of a `keycloak_realm` resource, which
  is the realm name.
- **Static keys.** Roles, groups and mappers are maps keyed by logical names.

## Ordering

`roles` and `groups` look up clients and roles by name with data sources. When those clients or
roles are created in the same configuration, add `depends_on` on the module call (as the example
does), so the lookups run after they exist.

## Secrets

Client secrets passed to these modules, and secrets Keycloak generates for confidential clients,
are stored in Terraform state. Keep state in the [`storage-backend`](../storage-backend) account
(Entra-only, encrypted, versioned) and pass secrets through `TF_VAR_*` variables from a secret
store such as Key Vault, never as literals.
