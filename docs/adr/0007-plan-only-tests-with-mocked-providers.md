# 0007. Plan-only tests with mocked providers

- Status: Accepted
- Date: 2026-09-30

## Context

Infrastructure modules need automated tests, but applying a full platform (firewall, AKS,
zone-redundant PostgreSQL) for every change is slow, expensive and requires credentials in CI.
`terraform validate` alone misses logic errors, such as a wrong default, a precondition that never
fires, or a `count` that can't be evaluated at plan time.

Terraform's native test framework supports `mock_provider` and `command = plan`, so modules can
be planned without Azure.

## Decision

- Every module with logic has `tests/<module>.tftest.hcl` with mocked providers and plan-only
  runs, and each example has one as well.
- Tests assert the secure defaults and the wiring of each feature, and use `expect_failures` to
  check that validations and preconditions reject unsafe input.
- CI runs `fmt`, `validate`, `test` for every module and example, and `trivy config` for
  misconfiguration scanning. `scripts/check.sh` runs the same gates locally.
- The example tests plan the full composition, which catches cross-module problems such as
  unknown values reaching `count`.

## Consequences

- Fast feedback with no credentials. The whole suite runs in about a minute.
- Mocks don't catch Azure API behaviour: quota, region or SKU availability, RBAC propagation, or
  service-specific validation at apply time. Those need an occasional real deployment to a
  sandbox subscription, which is a manual step for now.
