# Security

This is a reference platform, and its defaults are the security baseline: private endpoints,
Entra ID authentication only, customer-managed keys available everywhere, and all egress through
Azure Firewall. The reasoning is recorded in the [architecture decision records](docs/adr).

## Reporting a vulnerability

Please report vulnerabilities privately rather than in a public issue. Use the repository's
**Security** tab (private vulnerability reporting) or contact the repository owner directly.
Include the affected module, a description of the impact, and steps to reproduce if you have them.

## What not to commit

`*.tfvars`, `backend.hcl` and Terraform state contain environment details and must stay out of
git. Only the `*.example` files are tracked, and `.gitignore` enforces this. CI authenticates
with OpenID Connect, so no Azure credentials belong in the repository or in GitHub secrets.
