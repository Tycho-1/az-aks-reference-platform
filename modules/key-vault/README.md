# Key Vault module

Key Vault for **customer-managed keys** (CMK): AKS disk encryption and KMS etcd encryption, ACR,
and PostgreSQL. It favours private networking and RBAC authorization, and uses keys that rotate
automatically.

## What you get by default

| Area | Default |
|------|---------|
| SKU | `premium`, so keys are HSM-backed (`RSA-HSM`, 3072 bit) |
| Protection | Purge protection always on (every CMK integration requires it), 90-day soft delete |
| Access | Azure RBAC (no access policies). The deployer gets `Key Vault Crypto Officer`; consumers are granted roles by their own modules |
| Network | Public access disabled unless `allowed_ip_ranges` is set; trusted Azure services bypass; optional private endpoint |
| Keys | Automatic rotation after `P365D`, **no expiry date**. An expired key would break consumers pinned to a key version, such as AKS KMS |
| Logs | `audit` category group to Log Analytics |

## Usage

```hcl
module "key_vault" {
  source = "../../modules/key-vault"

  name                = "kv-platform-weu-ab12"
  resource_group_name = azurerm_resource_group.security.name
  location            = "westeurope"

  allowed_ip_ranges = ["203.0.113.10/32"] # Terraform runner, if it's outside the network
  private_endpoint = {
    subnet_id           = module.spoke.subnet_ids["private_endpoints"]
    private_dns_zone_id = module.hub.private_dns_zone_ids["key_vault"]
  }

  keys = {
    aks-disk = {}
    aks-kms  = { key_opts = ["encrypt", "decrypt", "wrapKey", "unwrapKey"] }
  }
}
```

The `keys` output exposes `id` (versioned) and `versionless_id` for each key. Use the versionless
ID where the service follows rotation automatically (disk encryption sets, ACR, PostgreSQL). Use
the versioned ID for AKS KMS.

## Notes

- **Where Terraform runs.** Key creation is a data-plane operation. With `allowed_ip_ranges`
  empty, Terraform must run from a network that reaches the private endpoint, such as a
  self-hosted runner in the spoke.
- **Destroy.** Purge protection means a deleted vault and its keys stay soft-deleted for the
  retention period, and the vault name cannot be reused until then.
- **Cross-region.** A vault in a paired region (for example, for PostgreSQL geo-backup keys) can
  have its private endpoint in the primary spoke. Set `private_endpoint.location` to the spoke's
  region.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allowed\_ip\_ranges | Public IPs/CIDRs allowed to reach the data plane (e.g. the Terraform runner). Empty disables public network access entirely; Terraform must then run from a network with private endpoint access. Trusted Azure services (disk encryption sets, ACR, PostgreSQL) are always allowed. | `list(string)` | `[]` | no |
| deployer\_crypto\_officer\_enabled | Grant the identity running Terraform Key Vault Crypto Officer so it can manage the keys. | `bool` | `true` | no |
| keys | Keys keyed by name. Keys rotate automatically after `rotate_after` (ISO 8601 duration) and never expire, because consumers pinned to a version (e.g. AKS KMS) would break on expiry. | ```map(object({ key_type = optional(string, "RSA-HSM") key_size = optional(number, 3072) key_opts = optional(list(string), ["wrapKey", "unwrapKey"]) rotate_after = optional(string, "P365D") }))``` | `{}` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace | Send audit logs to Log Analytics. Null disables diagnostics. | ```object({ id = string })``` | `null` | no |
| name | Globally unique Key Vault name (3-24 characters). | `string` | n/a | yes |
| private\_endpoint | Private endpoint for the vault. `private_dns_zone_id` should be a privatelink.vaultcore.azure.net zone. Set `location` when the subnet's VNet is in a different region than the vault. | ```object({ subnet_id = string private_dns_zone_id = string location = optional(string) })``` | `null` | no |
| resource\_group\_name | Name of an existing resource group. | `string` | n/a | yes |
| role\_assignments | Additional data plane role assignments keyed by a static name. | ```map(object({ principal_id = string role_definition_name = string principal_type = optional(string, "ServicePrincipal") }))``` | `{}` | no |
| sku\_name | premium enables HSM-backed keys (RSA-HSM), recommended for customer-managed keys. | `string` | `"premium"` | no |
| soft\_delete\_retention\_days | Soft delete retention (7-90). Purge protection is always on, as CMK scenarios require it. | `number` | `90` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the Key Vault. |
| keys | Keys keyed by name. Use `versionless_id` for services that follow rotation automatically (disk encryption sets, ACR, PostgreSQL) and `id` (versioned) for AKS KMS. |
| name | Name of the Key Vault. |
| vault\_uri | Data plane URI of the Key Vault. |
<!-- END_TF_DOCS -->
