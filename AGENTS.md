# AGENTS.md

Guidance for AI coding agents (Cursor, Claude Code, Codex, Copilot) working in this repository.
Human-facing documentation lives in [README.md](README.md) and the module READMEs. Architectural
decisions live in [docs/adr](docs/adr).

## What this repo is

Reusable Terraform modules for a production AKS platform on Azure (hub-and-spoke with Azure
Firewall, private AKS, ACR, PostgreSQL Flexible Server, Key Vault CMK) plus two root examples:

- `modules/<name>/`: reusable modules with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`, `tests/`
- `environments/dev/`: single VNet with NAT gateway egress (dev/test)
- `environments/prod/`: hub and spoke, firewall egress, private endpoints, CMK everywhere
- `bootstrap/`: one-off setup (e.g. GitHub Actions OIDC identities)
- `modules/keycloak/`: Keycloak realm modules (`keycloak/keycloak` 5.x), independent of the Azure
 platform but following the same conventions, tests and CI wiring

## Tooling

- Terraform `>= 1.11`, `azurerm` `>= 5.0, < 6.0`, `azuread` 3.x, `time`, `random`. CI tests `1.11.0` and `latest`; the production plan and apply workflow is pinned to `1.11.0`
- Run all quality gates with `scripts/check.sh` (or `scripts/check.sh modules/aks` for one dir).
  It also runs `tflint` and `terraform-docs --output-check` when those tools are installed.
- `terraform test` uses mocked providers and `command = plan`, so it needs no Azure credentials

## Hard rules

- **Never run `terraform apply`, `destroy`, `import` or `state` commands**, or anything that touches
  real Azure resources. Plan-only tests are the verification loop.
- **Modules never contain `provider` blocks.** Only root configurations (`environments/*`,
  `bootstrap/*`) configure
  providers and backends.
- **`count` and `for_each` must depend only on values known at plan time.** Use a nullable
  object wrapper (`log_analytics = { workspace_id = ... }`) and test `var.x != null`, never an ID
  that may be unknown. Don't wrap the test in `try()`: `try()` over an object that contains unknown
  values returns unknown. Use `var.x == null ? false : var.x.y != null` instead.
- **Secure by default.** Defaults target production: no public endpoints, Entra ID only, local
  auth disabled, diagnostics on. Relaxing a default must be an explicit input.
- Every behaviour change updates the module README and, where it makes sense, a test assertion.

## Conventions

- Inputs are grouped objects with `optional()` defaults and `validation` blocks. Cross-variable
  constraints go in `lifecycle.precondition` on the primary resource.
- Keys in `for_each` maps are static logical names (`aks_nodes`, `postgres`), never resource IDs.
- Role assignments a resource needs at creation time are created first, followed by a
  `time_sleep` (60s) for RBAC propagation and `depends_on` on the consumer.
- Resource-specific diagnostic tables: `log_analytics_destination_type = "Dedicated"`.
- Naming follows the [CAF abbreviations](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations)
  (`vnet-`, `snet-`, `aks-`, `kv-`, `cr`, `psql-`, `afw-`) and is done by callers, not modules.
- Comments state constraints the code can't express (Azure quirks, ordering). Don't narrate the code.
- Accepted security findings go in `.trivyignore` with a reason.

## azurerm v5 gotchas

- `service_endpoint {}` blocks, not `service_endpoints = []`
- `node_provisioning_profile { mode = "Manual" }` is required on `azurerm_kubernetes_cluster`
- NSG rules as separate `azurerm_network_security_rule` resources
- Key Vault: `rbac_authorization_enabled = true`; ACR: `encryption` and `network_rule_set` use attribute (list-of-object) syntax
- In mocks, `azurerm_client_config` needs UUID `tenant_id` and `object_id` values

## Definition of done

1. `scripts/check.sh` passes (fmt, validate, tests, tflint, terraform-docs, trivy).
2. README of each touched module is updated, including the generated reference between the
   `BEGIN_TF_DOCS` markers (`terraform-docs -c .terraform-docs.yml <module>`). New modules are
   added to the root README table,
   the CI matrix in `.github/workflows/terraform.yml` and `default_dirs` in `scripts/check.sh`.
3. Significant design choices get an ADR in `docs/adr/`.
