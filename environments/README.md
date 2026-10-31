# Environments

Deployable Terraform roots, one state file per folder. Each environment composes the shared
`modules/` for a distinct topology or maturity level.

| Folder | State key (see `backend.hcl.example`) | Purpose |
|--------|--------------------------------------|---------|
| [`dev`](dev) ([README](dev/README.md)) | `dev.tfstate` | Simple spoke, NAT egress, no hub/CMK; PostgreSQL optional (`postgres_enabled`, default off) |
| [`prod`](prod) ([README](prod/README.md)) | `prod.tfstate` | Hub-and-spoke, firewall, private endpoints, CMK, alerting, Flux |

Run quality gates: `scripts/check.sh environments/dev` or `scripts/check.sh environments/prod`.
