# 0006. Entra ID and managed identities instead of keys and passwords

- Status: Accepted
- Date: 2026-09-30

## Context

Shared secrets (storage account keys, ACR admin passwords, PostgreSQL passwords, cluster admin
kubeconfigs) are long-lived, hard to rotate, and end up in Terraform state, CI variables and
laptops. Every Azure service in this platform supports Entra ID authentication instead.

## Decision

- **Humans** authenticate with Entra ID and are authorised through groups. On AKS, local accounts
  are disabled and Azure RBAC for Kubernetes is enabled. Cluster admin is granted to groups, not
  users.
- **Workloads** use AKS workload identity (OIDC issuer and federated credentials) to reach
  PostgreSQL, Key Vault and other Azure services.
- **Services** use user-assigned managed identities: the AKS control plane, the kubelet (AcrPull),
  disk encryption, and the CMK identities.
- Local authentication is disabled by default: storage shared keys, the ACR admin user and
  anonymous pull, and PostgreSQL password auth. When PostgreSQL password auth is explicitly
  enabled, the password goes through an ephemeral variable and a write-only argument, so it never
  lands in state.

## Consequences

- No credentials to rotate or leak for normal operation, and access is audited in Entra ID.
- Access depends on correct Entra group membership, and on RBAC propagating before resources
  that need it (hence the `time_sleep` pattern in the modules).
- Tools that only support passwords (some legacy database clients) need workarounds such as
  fetching Entra tokens as passwords.
