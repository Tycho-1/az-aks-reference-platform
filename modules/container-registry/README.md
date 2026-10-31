# Container registry module

Private Azure Container Registry for the platform's images, following the
[ACR best practices](https://learn.microsoft.com/azure/container-registry/container-registry-best-practices).

## What you get by default

| Area | Default |
|------|---------|
| SKU | `Premium`, which private endpoints, zone redundancy, geo-replication, retention and CMK require |
| Access | Entra ID only: admin user and anonymous pull disabled. Grant `AcrPull` to the AKS kubelet identity (the AKS module does this via `acr_ids`) and `AcrPush` to CI through `role_assignments` |
| Network | Public access disabled unless `allowed_ip_ranges` is set; export policy blocks copying images out of a private registry; trusted services bypass |
| Resilience | Zone redundant; optional geo-replicas with global endpoint routing |
| Hygiene | Untagged manifests deleted after 7 days |
| Encryption | Optional customer-managed key via a dedicated user-assigned identity |

## Usage

```hcl
module "acr" {
  source = "../../modules/container-registry"

  name                = "crplatformweuab12"
  resource_group_name = azurerm_resource_group.aks.name
  location            = "westeurope"

  private_endpoint = {
    subnet_id           = module.spoke.subnet_ids["private_endpoints"]
    private_dns_zone_id = module.hub.private_dns_zone_ids["acr"]
  }

  customer_managed_key = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["acr"].versionless_id
  }

  role_assignments = {
    ci-push = { principal_id = "<ci-identity-object-id>", role_definition_name = "AcrPush" }
  }
}
```

## Notes

- **CMK is creation-time only.** Enabling or disabling it later forces a new registry. Use a
  versionless key ID so rotated key versions are picked up automatically.
- **CI pushes.** A private registry is only reachable from inside the network. Either run CI on a
  self-hosted runner in the spoke, or allow the runner's egress IPs with `allowed_ip_ranges`.
  Hosted CI runners have changing IPs, so prefer a self-hosted runner.
- The preconditions reject configurations that Azure would fail at apply time: Premium-only
  features on a lower SKU, and a registry with neither public nor private access.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| allowed\_ip\_ranges | Public CIDRs allowed to reach the registry (e.g. hosted CI runners). Empty disables public network access. | `list(string)` | `[]` | no |
| customer\_managed\_key | Encrypt registry content with a Key Vault key. Only possible at creation time. Use a versionless key ID so ACR picks up rotated key versions automatically. | ```object({ key_vault_id = string key_vault_key_id = string })``` | `null` | no |
| georeplications | Additional replica regions keyed by location, for regional resilience and pull locality. | ```map(object({ zone_redundancy_enabled = optional(bool, true) }))``` | `{}` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace | Send registry logs and metrics to Log Analytics. Null disables diagnostics. | ```object({ id = string })``` | `null` | no |
| name | Globally unique registry name (5-50 alphanumerics). | `string` | n/a | yes |
| private\_endpoint | Private endpoint for the registry. `private_dns_zone_id` should be a privatelink.azurecr.io zone. Set `location` when the subnet's VNet is in a different region than the registry. | ```object({ subnet_id = string private_dns_zone_id = string location = optional(string) })``` | `null` | no |
| resource\_group\_name | Name of an existing resource group. | `string` | n/a | yes |
| role\_assignments | Registry role assignments keyed by a static name, e.g. AcrPush for a CI identity. | ```map(object({ principal_id = string role_definition_name = string principal_type = optional(string, "ServicePrincipal") }))``` | `{}` | no |
| sku | Premium is required for private endpoints, zone redundancy, geo-replication, retention and CMK. | `string` | `"Premium"` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| untagged\_manifest\_retention\_days | Delete untagged manifests after this many days. Null disables the retention policy. | `number` | `7` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the registry. Pass to the AKS module's `acr_ids` to grant AcrPull to the kubelet. |
| login\_server | Login server, e.g. crplatformprod.azurecr.io. |
| name | Name of the registry. |
<!-- END_TF_DOCS -->
