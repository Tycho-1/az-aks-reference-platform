# 0003. Customer-managed keys are opt-in per module

- Status: Accepted
- Date: 2026-09-30

## Context

Azure encrypts all data at rest with platform-managed keys by default. Customer-managed keys
(CMK) in Key Vault add key ownership, the ability to revoke access, and an audit trail of key
use. Frameworks such as ISO 27001, PCI DSS and some sector regulations often require these.

CMK also adds operational risk and cost. If a key is deleted, disabled or expires, or the vault
becomes unreachable, the service can't read its data. CMK needs purge protection, Premium SKUs
(ACR) and extra identities and role assignments. Several services only accept it at creation
time.

## Decision

- Every module that supports CMK exposes it as an optional input (`disk_encryption` and `kms`
  on AKS, `customer_managed_key` on ACR and PostgreSQL), with `null` as the default.
- When CMK is enabled, the module creates a dedicated user-assigned identity, grants it the
  minimum Key Vault role, and waits for RBAC propagation before creating the resource.
- The `key-vault` module enforces purge protection and creates HSM-backed RSA keys that rotate
  automatically and have **no expiry date**.
- Consumers that follow rotation (the disk encryption set, ACR, PostgreSQL) get a versionless
  key ID. AKS KMS gets a versioned ID, as it requires.
- `environments/prod` enables CMK for disks, etcd secrets, ACR and PostgreSQL, including a
  paired-region key for PostgreSQL geo-redundant backups. `environments/dev` does not.

## Consequences

- Teams that don't need CMK aren't forced into its cost and failure modes.
- Enabling CMK on an existing ACR or PostgreSQL server forces replacement, so it must be
  decided up front.
- AKS KMS uses the KMS etcd encryption integration that `azurerm` currently supports. After a
  key rotation, the key version in the input must be updated. Revisit this when the provider
  supports Microsoft's newer KMS experience with platform-managed rotation.
