# Terraform state backend module

Storage account and containers for Terraform remote state, hardened to the
[Azure Storage security baseline](https://learn.microsoft.com/security/benchmark/azure/baselines/storage-security-baseline).

## What you get by default

| Area | Default |
|------|---------|
| Authentication | **Entra ID only**: shared keys, SAS, and local users are disabled. Access goes through `Storage Blob Data Contributor` role assignments |
| Network | Firewall default-deny, with allow-listed IPs/subnets and trusted Azure services |
| Data protection | Blob versioning, change feed, 30-day blob and container soft delete, ZRS |
| Encryption | TLS 1.2 minimum, HTTPS only, infrastructure (double) encryption |
| Protection | `CanNotDelete` lock, no public blobs, no cross-tenant replication |
| Audit | Optional blob audit logs to Log Analytics |

The previous version stored the account key in Key Vault. That is no longer needed: with Entra
auth there is no key to protect, and the backend authenticates with the caller's identity.

## Usage

See [`examples/bootstrap`](./examples/bootstrap) for a runnable example. Because shared keys are
disabled, the calling provider needs `storage_use_azuread = true`.

```hcl
module "state" {
  source = "../../modules/storage-backend"

  storage_account_name = "sttfstateplatform001"
  resource_group_name  = azurerm_resource_group.tfstate.name
  location             = "westeurope"
  container_names      = ["platform-dev", "platform-prod"]

  network_access = {
    ip_rules = ["203.0.113.10"]
  }

  state_contributors = {
    github_actions = { principal_id = "<ci-identity-object-id>" }
  }
}
```

Consumers then use a backend configuration like this:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-mgmt-weu"
    storage_account_name = "sttfstateplatform001"
    container_name       = "platform-prod"
    key                  = "aks.tfstate"
    use_azuread_auth     = true
  }
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `storage_account_name` | Globally unique name | required |
| `resource_group_name`, `location` | Placement | required |
| `account_replication_type` | `ZRS` / `GZRS` recommended | `ZRS` |
| `container_names` | State containers | `["tfstate"]` |
| `blob_soft_delete_retention_days` | Blob recovery window | `30` |
| `container_soft_delete_retention_days` | Container recovery window | `30` |
| `network_access` | `{ public_network_access, default_action, ip_rules, subnet_ids }` | public, default deny |
| `state_contributors` | Principals granted blob data access | `{}` |
| `log_analytics_workspace` | `{ id }` for audit logs | `null` |
| `delete_lock_enabled` | `CanNotDelete` lock | `true` |
| `tags` | Tags | `{}` |

## Outputs

`storage_account_id`, `storage_account_name`, `containers`, `backend_configs`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| account\_replication\_type | Replication. ZRS survives a zone outage; GZRS additionally replicates to the paired region. | `string` | `"ZRS"` | no |
| blob\_soft\_delete\_retention\_days | Days deleted or overwritten state blobs remain recoverable. | `number` | `30` | no |
| container\_names | Blob containers to create for state (e.g. one per environment or stack). | `list(string)` | ```[ "tfstate" ]``` | no |
| container\_soft\_delete\_retention\_days | Days deleted containers remain recoverable. | `number` | `30` | no |
| delete\_lock\_enabled | Add a CanNotDelete management lock on the storage account. | `bool` | `true` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace | Send blob audit logs to Log Analytics. Null disables diagnostics. | ```object({ id = string })``` | `null` | no |
| network\_access | Data plane network access. Public access is enabled but defaults to deny, so only the listed IPs, subnets and trusted Azure services can read state. Add your CI runner egress IPs here, or set `public_network_access = "Disabled"` and use a private endpoint. | ```object({ public_network_access = optional(string, "Enabled") default_action = optional(string, "Deny") ip_rules = optional(list(string), []) subnet_ids = optional(list(string), []) })``` | `{}` | no |
| resource\_group\_name | Name of an existing resource group. | `string` | n/a | yes |
| state\_contributors | Principals (CI identities, platform engineers group) granted Storage Blob Data Contributor, keyed by a static name. | ```map(object({ principal_id = string principal_type = optional(string, "ServicePrincipal") }))``` | `{}` | no |
| storage\_account\_name | Globally unique storage account name (3-24 lowercase letters and digits). | `string` | n/a | yes |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| backend\_configs | Ready-to-use azurerm backend settings per container. Set `key` per stack, e.g. "platform/aks.tfstate". |
| containers | Created containers keyed by name. |
| storage\_account\_id | ID of the storage account. |
| storage\_account\_name | Name of the storage account. |
<!-- END_TF_DOCS -->
