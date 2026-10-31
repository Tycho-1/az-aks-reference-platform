# 0008. OpenID Connect for CI/CD, with least-privilege identities

- Status: Accepted
- Date: 2026-09-30

## Context

A pipeline that applies infrastructure needs strong credentials, and storing them as long-lived
secrets in GitHub is the usual weak point: they leak, they don't expire, and they tend to be
granted Owner "so that everything works".

GitHub Actions can request an OIDC token for a workflow run, and Azure can trust that token
through a federated credential on a managed identity. The trust can be pinned to a specific
GitHub environment, and environments can require reviewers and restrict which branches deploy.

## Decision

- [`bootstrap/github-actions-identity`](../../bootstrap/github-actions-identity) creates two
  user-assigned identities, each trusting exactly one GitHub environment:
  `production-plan` for the plan identity and `production` for the apply identity.
- The plan identity gets `Reader` and `Key Vault Reader` on the subscription, plus state
  container access so it can lock state.
- The apply identity gets `Contributor`, plus `Role Based Access Control Administrator` with an
  ABAC condition that forbids granting or removing the Owner, User Access Administrator and
  RBAC Administrator roles. The platform creates role assignments (AcrPull, Key Vault, network),
  so it needs RBAC write, but it must not be able to escalate itself.
- [`deploy-production.yml`](../../.github/workflows/deploy-production.yml) plans on pull
  requests and applies only from `main`, and only after the protected `production` environment
  approves. It applies the exact plan artifact that was reviewed.
- All GitHub Actions are pinned to commit SHAs.

## Consequences

- No Azure credentials exist in GitHub, and a pull request from any branch can do nothing but
  read.
- The `production` environment must be configured with required reviewers and a `main`-only
  branch rule. The protection lives in GitHub settings, not in this repository, so it is part of
  the setup checklist.
- The identities are scoped to one subscription. Additional environments get their own identity
  pair instead of a wider scope.
