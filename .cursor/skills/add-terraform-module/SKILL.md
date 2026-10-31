---
name: add-terraform-module
description: Scaffolds a new reusable Terraform module in modules/ with the repo's file layout, secure defaults, mocked-provider tests, README and CI wiring. Use when the user asks to add, create or scaffold a new module or Azure component (e.g. Bastion, App Gateway, Service Bus).
---

# Add a Terraform module

Copy this checklist and tick it off:

```
- [ ] 1. Research the service's security baseline
- [ ] 2. Create files from the templates
- [ ] 3. Implement resources with secure defaults
- [ ] 4. Write tests
- [ ] 5. Write README
- [ ] 6. Wire into repo (root README, CI, check script)
- [ ] 7. scripts/check.sh modules/<name> passes
```

## 1. Research

Read the Azure security baseline and the Well-Architected service guide for the service. Note:
the network isolation options, Entra-only auth, zone redundancy, diagnostics categories, CMK
support, and creation-time-only settings. Check the azurerm v5 resource schema. v5 renamed or
converted several blocks (see AGENTS.md).

## 2. Files

Create `modules/<name>/` with `versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`,
`tests/<name>.tftest.hcl`. Start from [templates.md](templates.md).

## 3. Implementation rules

- Standard inputs first: `name`, `resource_group_name`, `location`, then feature objects, then `log_analytics_workspace`, `tags`.
- Optional features are nullable objects; `count = var.feature != null ? 1 : 0`.
- No provider blocks. No naming logic: the caller passes `name`.
- Private endpoint pattern: `private_endpoint = { subnet_id, private_dns_zone_id, location = optional }`.
- CMK pattern: dedicated user-assigned identity, `Key Vault Crypto Service Encryption User`, `time_sleep` 60s, `depends_on`.
- Preconditions for combinations Azure would reject at apply time (e.g. SKU-gated features).

## 4. Tests

Follow `.cursor/rules/terraform-tests.mdc`: one secure-defaults run, one run per feature, and
negative runs for every validation and precondition.

## 5. README

Sections: intro (what and why), "What you get by default" table, Usage (HCL), Key inputs table, Outputs, Notes.
Match the tone of `modules/key-vault/README.md`.

## 6. Wiring

- Add a row to the Modules table in the root `README.md`
- Add the dir to the matrix in `.github/workflows/terraform.yml`
- Add the dir to `default_dirs` in `scripts/check.sh`
- If it introduces a design decision, add an ADR (`docs/adr/`, next number, template in `docs/adr/README.md`)

## 7. Verify

Run `scripts/check.sh modules/<name>`, then `scripts/check.sh` for the whole repo if an environment uses it.
