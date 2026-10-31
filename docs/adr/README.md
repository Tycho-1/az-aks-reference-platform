# Architecture decision records

Significant design decisions for this platform, in the
[Nygard format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions).
Records are immutable once accepted: to change a decision, add a new ADR that supersedes the old one.

| ADR | Decision | Status |
|-----|----------|--------|
| [0001](0001-separate-modules-by-lifecycle.md) | Separate modules by lifecycle; PostgreSQL is not part of the AKS module | Accepted |
| [0002](0002-hub-and-spoke-with-azure-firewall.md) | Hub-and-spoke with Azure Firewall for production egress | Accepted |
| [0003](0003-customer-managed-keys-opt-in.md) | Customer-managed keys are opt-in per module | Accepted |
| [0004](0004-private-endpoints-and-central-dns.md) | Private by default, with central private DNS in the hub | Accepted |
| [0005](0005-terraform-stops-at-the-cluster-boundary.md) | Terraform stops at the cluster boundary; GitOps delivers in-cluster software | Accepted |
| [0006](0006-identity-over-secrets.md) | Entra ID and managed identities instead of keys and passwords | Accepted |
| [0007](0007-plan-only-tests-with-mocked-providers.md) | Plan-only tests with mocked providers | Accepted |
| [0008](0008-oidc-for-cicd-with-least-privilege.md) | OpenID Connect for CI/CD with least-privilege identities | Accepted |

## Template

```markdown
# NNNN. Title

- Status: Proposed | Accepted | Superseded by NNNN
- Date: YYYY-MM-DD

## Context

What forces are at play: requirements, constraints, Azure guidance.

## Decision

What we do, stated in full sentences.

## Consequences

What becomes easier, what becomes harder, and what we accept as trade-offs.
```
