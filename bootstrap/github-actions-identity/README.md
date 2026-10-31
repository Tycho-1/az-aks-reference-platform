# GitHub Actions identities

One-off setup for [`deploy-production.yml`](../../.github/workflows/deploy-production.yml).
That workflow skips its jobs while `AZURE_TENANT_ID` is empty, and plans on the next run
once this bootstrap is applied and the variables below are set. It creates two
user-assigned managed identities that GitHub Actions signs in to with
[OpenID Connect](https://learn.microsoft.com/azure/developer/github/connect-from-azure-openid-connect),
so no Azure credentials are stored in GitHub.

| Identity | Trusted subject | Permissions |
|----------|-----------------|-------------|
| `id-github-plan` | `environment:production-plan` | `Reader` + `Key Vault Reader` on the subscription, `Storage Blob Data Contributor` on the state container (for locking) |
| `id-github-apply` | `environment:production` | `Contributor` on the subscription, `Role Based Access Control Administrator` **restricted so it can't grant or remove Owner, User Access Administrator or RBAC Administrator**, and state access |

Pull requests can only plan. Changing Azure requires the `production` environment, which you
protect with required reviewers and a `main`-only branch rule.

## Setup

```sh
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars   # repository, state account ID
terraform init -backend-config=backend.hcl
terraform apply
terraform output github_variables
```

Run this once, as an Owner of the subscription. The identities can't create themselves.

Then configure the GitHub repository (Settings, Environments, and Secrets and variables):

| Where | Name | Value |
|-------|------|-------|
| Repository variable | `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | from `github_variables` |
| Repository variable | `TFSTATE_RESOURCE_GROUP`, `TFSTATE_STORAGE_ACCOUNT`, `TFSTATE_CONTAINER` | state storage |
| Repository variable (optional) | `TERRAFORM_RUNNER` | label of a self-hosted runner in the network |
| Environment `production-plan` variable | `AZURE_CLIENT_ID` | `AZURE_CLIENT_ID_PLAN` |
| Environment `production` variable | `AZURE_CLIENT_ID` | `AZURE_CLIENT_ID_APPLY` |
| Environment `production` protection | Required reviewers, deployment branch `main` | |
| Repository secret | `TFVARS_PRODUCTION` | contents of `environments/prod/terraform.tfvars` |

## Notes

- **Private resources need a private runner.** Terraform reads Key Vault keys through the data
  plane, and the production vaults have no public access, so hosted runners can't refresh them. Run
  a self-hosted runner in the spoke (for example, Container Apps jobs or a VM scale set with a
  managed identity) and set `TERRAFORM_RUNNER` to its label.
- **Scope.** The identities are scoped to one subscription. With several environments, create
  one identity pair per environment and subscription, rather than widening the scope.
