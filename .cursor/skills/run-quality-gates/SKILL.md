---
name: run-quality-gates
description: Runs and fixes the repo's Terraform quality gates (fmt, validate, mocked-provider terraform test, trivy config). Use before finishing any Terraform change, when the user asks to check, lint, validate or test the modules, or when CI fails.
---

# Run quality gates

1. Run the script (whole repo, or only the dirs you touched):

```bash
scripts/check.sh
scripts/check.sh modules/aks environments/prod
```

2. Fix failures by type:

| Failure | Fix |
|---------|-----|
| `fmt -check` | `terraform fmt -recursive <dir>` |
| `Invalid count argument` / `Invalid for_each argument` | The condition depends on an unknown value. Make it depend on a nullable input object instead (see `.cursor/rules/terraform-modules.mdc`) |
| `Unsupported argument` / `Unsupported block type` | azurerm v5 schema change; check the provider docs and AGENTS.md gotchas |
| `expected "tenant_id" to be a valid UUID` in tests | Add `mock_data "azurerm_client_config"` with UUID defaults |
| Test assertion fails | Decide whether the code or the test is wrong. Never weaken a security assertion to make it pass |
| trivy finding | Fix it. Only if the finding is a deliberate, documented trade-off, add the ID to `.trivyignore` with a reason comment |

3. Re-run until the script prints `All checks passed.`

Plan-only. Never "verify" by running `terraform apply`.
