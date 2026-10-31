# AKS module

Production-oriented Azure Kubernetes Service cluster, aligned with the
[AKS baseline architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
and the [Well-Architected AKS service guide](https://learn.microsoft.com/azure/well-architected/service-guides/azure-kubernetes-service).

The module manages the cluster and its Azure-side dependencies only. It deliberately does **not**:

- create the VNet or subnets (use [`../network`](../network) or your landing zone's spoke),
- configure `kubernetes`/`helm` providers or install charts. In-cluster components are delivered by
  GitOps (optional Flux extension below), which avoids provider-inside-module coupling and the
  "cluster and its contents in one apply" problem.

## What you get by default

| Area | Default |
|------|---------|
| Control plane | `Standard` tier (uptime SLA), minor version pinned, `patch` auto-upgrade, node OS `NodeImage` channel, planned maintenance windows |
| Identity | User-assigned control plane and kubelet identities, RBAC pre-granted before cluster creation |
| Access | Entra ID integration with Azure RBAC, **local accounts disabled**, admin via Entra groups |
| Workload auth | OIDC issuer + workload identity, Key Vault Secrets Store CSI driver with rotation |
| Networking | Azure CNI Overlay powered by Cilium (eBPF data plane + network policy), Standard LB, configurable egress (NAT gateway / UDR) |
| API server | Authorized IP ranges or private cluster; optional API server VNet integration |
| Node pools | System pool tainted `CriticalAddonsOnly`, 3 zones, autoscaling, Azure Linux, ephemeral OS disks, 33% max surge; user pools default to **Spot** (override with `priority = "Regular"` for production) |
| Governance | Azure Policy add-on, Image Cleaner, cost analysis |
| Observability | Container Insights (MSI auth), control plane logs to resource-specific tables, managed Prometheus, optional Defender for Containers |
| Encryption (opt-in) | Customer-managed keys for OS/data disks (disk encryption set) and Kubernetes secrets in etcd (KMS), with all required role assignments |

## Usage

```hcl
module "aks" {
  source = "../../modules/aks"

  name                = "aks-platform-prod-weu"
  resource_group_name = "rg-platform-prod-weu-aks"
  location            = "westeurope"
  kubernetes_version  = "1.37"

  node_subnet_id = module.network.subnet_ids["aks_nodes"]
  network_profile = {
    outbound_type = "userAssignedNATGateway"
  }

  admin_group_object_ids          = ["<entra-group-object-id>"]
  api_server_authorized_ip_ranges = ["203.0.113.0/24"]

  node_pools = {
    apps = {
      vm_size   = "Standard_D4ds_v5"
      min_count = 3
      max_count = 10
    }
  }

  log_analytics = {
    workspace_id     = azurerm_log_analytics_workspace.this.id
    defender_enabled = true
  }

  managed_prometheus = {
    monitor_workspace_id = azurerm_monitor_workspace.this.id
  }
}
```

Access the cluster with Entra ID (requires [kubelogin](https://azure.github.io/kubelogin/)):

```sh
az aks get-credentials -g rg-platform-prod-weu-aks -n aks-platform-prod-weu
kubelogin convert-kubeconfig -l azurecli
```

## Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `name`, `resource_group_name`, `location` | Placement | required |
| `node_subnet_id` | Subnet for nodes; the VNet gets `Network Contributor` for the control plane identity | required |
| `kubernetes_version` | Minor version only (e.g. `1.33`); patches are applied automatically | `null` (AKS default) |
| `sku_tier` | `Free`, `Standard`, `Premium` | `Standard` |
| `admin_group_object_ids` | Entra groups with cluster-admin (required while local accounts are disabled) | `[]` |
| `api_server_authorized_ip_ranges` | Allowed CIDRs for a public API server | `[]` (warns) |
| `private_cluster` | `{ enabled, private_dns_zone_id, public_fqdn_enabled }` | disabled |
| `api_server_vnet_integration` | `{ subnet_id }` for a delegated API server subnet | `null` |
| `network_profile` | Pod/service CIDRs and `outbound_type` | overlay defaults, `loadBalancer` |
| `system_node_pool` | System pool sizing and OS settings | 3-5 × `Standard_D4ds_v5`, zones 1-3 |
| `node_pools` | Map of user pools | `{}` |
| `acr_ids` | Registries the kubelet identity can pull from | `{}` |
| `control_plane_role_assignments` | Extra roles for the control plane identity, granted before cluster creation (e.g. route table, private DNS zone) | `{}` |
| `disk_encryption` | `{ key_vault_id, key_vault_key_id }`: creates a disk encryption set with automatic key rotation | `null` |
| `kms` | `{ key_vault_id, key_vault_key_id, network_access }`: etcd encryption with a Key Vault key | `null` |
| `log_analytics` | Container Insights, diagnostics, Defender | `null` |
| `managed_prometheus` | Azure Monitor workspace for Prometheus metrics | `null` |
| `web_app_routing` | Managed ingress add-on | `null` |
| `workload_autoscaler` | Managed KEDA / VPA | disabled |
| `gitops` | Flux repository and kustomizations | `null` |

See [`variables.tf`](./variables.tf) for the full list and validation rules.

## Outputs

`id`, `name`, `fqdn`, `private_fqdn`, `current_kubernetes_version`, `node_resource_group`,
`oidc_issuer_url`, `web_app_routing_enabled`, `node_pool_priorities`, `node_pool_vm_sizes`,
`system_node_pool_vm_size`, `control_plane_identity`,
`kubelet_identity`, `key_vault_secrets_provider_identity`, `get_credentials_command`.

No kubeconfig is exported: with local accounts disabled, credentials come from Entra ID.

## Operational notes

- **Host encryption** (`host_encryption_enabled`) is recommended but requires the
  `Microsoft.Compute/EncryptionAtHost` feature on the subscription, so it is opt-in.
- **Ephemeral OS disks** require a VM size whose cache or temp disk fits the OS disk. Set
  `os_disk_type = "Managed"` for sizes without a local disk.
- **Ingress**: the community ingress-nginx project has been retired. Prefer the managed
  application routing add-on (`web_app_routing`), Application Gateway for Containers, or a
  Gateway API implementation delivered via GitOps.
- **Egress control**: for regulated workloads, route egress through Azure Firewall in a hub
  (`outbound_type = "userDefinedRouting"`) instead of a NAT gateway. The control plane identity
  needs `Network Contributor` on the route table (via `control_plane_role_assignments`). See
  [`environments/prod`](../../environments/prod).
- **Private cluster with a hub DNS zone**: pass the hub's `privatelink.<region>.azmk8s.io` zone
  as `private_cluster.private_dns_zone_id` and grant `Private DNS Zone Contributor` on it. AKS links
  the zone to the cluster VNet itself.
- **Disk encryption set**: pass a *versionless* key ID. The disk encryption set follows key
  rotation, and it works with ephemeral OS disks. Changing it on an existing cluster forces
  replacement.
- **KMS**: pass a *versioned* key ID and never let the key expire. A private vault
  (`network_access = "Private"`) requires `api_server_vnet_integration`. When the key rotates,
  update the key ID in the input so AKS re-encrypts the secrets. This uses the
  [KMS etcd encryption](https://learn.microsoft.com/azure/aks/use-kms-etcd-encryption) that
  `azurerm` supports today. Microsoft's newer KMS experience, with platform-managed rotation, is
  not yet exposed by the provider.

## Tests

```sh
terraform init -backend=false
terraform test
```

Tests run `plan` against a mocked `azurerm` provider, so they need no Azure credentials.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| acr\_ids | Container registry IDs the kubelet identity gets AcrPull on, keyed by a static name. | `map(string)` | `{}` | no |
| admin\_group\_object\_ids | Entra ID group object IDs granted cluster-admin. Required because local accounts are disabled by default. | `list(string)` | `[]` | no |
| api\_server\_authorized\_ip\_ranges | CIDRs allowed to reach a public API server. Strongly recommended when the cluster is not private. | `list(string)` | `[]` | no |
| api\_server\_vnet\_integration | API server VNet integration: projects the API server into a delegated subnet. Null disables it. | ```object({ subnet_id = string })``` | `null` | no |
| automatic\_upgrade\_channel | Cluster auto-upgrade channel. 'patch' keeps the pinned minor version patched. | `string` | `"patch"` | no |
| azure\_policy\_enabled | Enable the Azure Policy add-on (Gatekeeper) to enforce the AKS policy initiatives. | `bool` | `true` | no |
| control\_plane\_role\_assignments | Extra roles for the control plane identity, granted before the cluster is created and keyed by a static name. Typical entries: Network Contributor on a route table in another resource group (outbound\_type = userDefinedRouting) and Private DNS Zone Contributor on a central privatelink.<region>.azmk8s.io zone (private cluster). | ```map(object({ scope = string role_definition_name = string }))``` | `{}` | no |
| cost\_analysis\_enabled | Enable AKS cost analysis (requires Standard or Premium tier). | `bool` | `true` | no |
| disk\_encryption | Encrypt node OS and data disks with a customer-managed key through a disk encryption set. Only possible at cluster creation. Use a versionless key ID so rotation is picked up automatically. | ```object({ key_vault_id = string key_vault_key_id = string })``` | `null` | no |
| dns\_prefix | DNS prefix for the API server FQDN. Defaults to the cluster name. | `string` | `null` | no |
| gitops | Optional Flux v2 (AKS GitOps extension) bootstrap. In-cluster platform components (cert-manager, ingress, policies, etc.) should be delivered from Git instead of Terraform. The repository must be public or reachable with `https_user` + a PAT supplied separately. | ```object({ repository_url = string branch = optional(string, "main") kustomizations = map(object({ path = string depends_on = optional(list(string), []) prune = optional(bool, true) })) })``` | `null` | no |
| image\_cleaner\_interval\_hours | Interval for Image Cleaner (removes unused, vulnerable images from nodes). Null disables it. | `number` | `168` | no |
| key\_vault\_secrets\_provider | Secrets Store CSI driver for Key Vault. Pair with workload identity instead of Kubernetes secrets. | ```object({ enabled = optional(bool, true) secret_rotation_interval = optional(string, "2m") })``` | `{}` | no |
| kms | Encrypt Kubernetes secrets in etcd with a Key Vault key (KMS). `key_vault_key_id` must be the versioned key ID. `network_access = "Private"` requires api\_server\_vnet\_integration and a private endpoint for the vault in the cluster VNet. | ```object({ key_vault_id = string key_vault_key_id = string network_access = optional(string, "Private") })``` | `null` | no |
| kubernetes\_version | Kubernetes minor version, e.g. "1.33". Pin the minor only: patch versions are applied by `automatic_upgrade_channel = "patch"` without causing Terraform drift. Null uses the AKS default. | `string` | `null` | no |
| local\_account\_disabled | Disable the static local admin kubeconfig so all access goes through Entra ID. | `bool` | `true` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics | Log Analytics integration: Container Insights, control plane diagnostic logs and (optionally) the Defender for Containers sensor. `kube-audit-admin` is the cost-effective audit category; add `kube-audit` only if you need read events too. Null disables all of it. | ```object({ workspace_id = string container_insights_enabled = optional(bool, true) defender_enabled = optional(bool, false) diagnostic_log_categories = optional(list(string), ["kube-audit-admin", "guard", "kube-controller-manager", "cluster-autoscaler"]) })``` | `null` | no |
| maintenance\_window\_auto\_upgrade | Planned maintenance window for cluster upgrades. Times are in `utc_offset`. | ```object({ frequency = optional(string, "Weekly") interval = optional(number, 1) duration = optional(number, 4) day_of_week = optional(string, "Sunday") start_time = optional(string, "02:00") utc_offset = optional(string, "+00:00") })``` | `{}` | no |
| maintenance\_window\_node\_os | Planned maintenance window for node OS image updates. | ```object({ frequency = optional(string, "Weekly") interval = optional(number, 1) duration = optional(number, 4) day_of_week = optional(string, "Saturday") start_time = optional(string, "02:00") utc_offset = optional(string, "+00:00") })``` | `{}` | no |
| managed\_prometheus | Azure Monitor managed Prometheus. Null disables it. | ```object({ monitor_workspace_id = string })``` | `null` | no |
| name | Name of the AKS cluster (e.g. aks-platform-prod-weu). | `string` | n/a | yes |
| network\_profile | Cluster networking. The module always uses Azure CNI Overlay with the Cilium data plane, which is Microsoft's recommended default for new clusters (eBPF data plane, network policy, no pod IP exhaustion in the VNet). | ```object({ pod_cidr = optional(string, "10.244.0.0/16") service_cidr = optional(string, "10.245.0.0/16") dns_service_ip = optional(string, "10.245.0.10") outbound_type = optional(string, "loadBalancer") })``` | `{}` | no |
| node\_os\_upgrade\_channel | Node OS security patching channel. | `string` | `"NodeImage"` | no |
| node\_pools | Additional user node pools keyed by pool name (max 12 lowercase alphanumeric characters). | ```map(object({ vm_size = string zones = optional(list(string), ["1", "2", "3"]) auto_scaling_enabled = optional(bool, true) node_count = optional(number) min_count = optional(number, 1) max_count = optional(number, 5) max_pods = optional(number, 110) os_sku = optional(string, "AzureLinux") os_disk_type = optional(string, "Ephemeral") os_disk_size_gb = optional(number) host_encryption_enabled = optional(bool, false) vnet_subnet_id = optional(string) priority = optional(string, "Spot") spot_max_price = optional(number, -1) node_labels = optional(map(string), {}) node_taints = optional(list(string), []) max_surge = optional(string, "33%") drain_timeout_in_minutes = optional(number, 30) tags = optional(map(string), {}) }))``` | `{}` | no |
| node\_resource\_group\_name | Name of the AKS-managed node resource group. Defaults to MC\_<rg>\_<cluster>\_<region>. | `string` | `null` | no |
| node\_subnet\_id | Subnet ID for the system node pool (and user pools that don't set their own subnet). | `string` | n/a | yes |
| private\_cluster | Private API server. `private_dns_zone_id` may be "System", "None" or the ID of a privatelink.<region>.azmk8s.io zone (required for hub-and-spoke with central DNS). | ```object({ enabled = optional(bool, false) private_dns_zone_id = optional(string, "System") public_fqdn_enabled = optional(bool, false) })``` | `{}` | no |
| resource\_group\_name | Name of an existing resource group for the cluster resource. | `string` | n/a | yes |
| sku\_tier | Control plane tier. Standard provides the financially backed uptime SLA and is recommended for production. | `string` | `"Standard"` | no |
| system\_node\_pool | System node pool. It is tainted with CriticalAddonsOnly so application workloads land on user pools. Microsoft recommends at least three nodes across availability zones. | ```object({ name = optional(string, "system") vm_size = optional(string, "Standard_D4ds_v5") zones = optional(list(string), ["1", "2", "3"]) min_count = optional(number, 3) max_count = optional(number, 5) max_pods = optional(number, 110) os_sku = optional(string, "AzureLinux") os_disk_type = optional(string, "Ephemeral") os_disk_size_gb = optional(number) host_encryption_enabled = optional(bool, false) max_surge = optional(string, "33%") drain_timeout_in_minutes = optional(number, 30) temporary_name_for_rotation = optional(string, "systemtmp") })``` | `{}` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| web\_app\_routing | Managed application routing add-on (Microsoft-managed ingress). Null disables it. Pass Azure DNS zone IDs to let it manage records. | ```object({ dns_zone_ids = optional(list(string), []) })``` | `null` | no |
| workload\_autoscaler | Managed KEDA and Vertical Pod Autoscaler add-ons. | ```object({ keda_enabled = optional(bool, false) vertical_pod_autoscaler_enabled = optional(bool, false) })``` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| control\_plane\_identity | User-assigned identity of the cluster control plane. |
| current\_kubernetes\_version | Kubernetes version currently running, including auto-applied patches. |
| fqdn | Public FQDN of the API server (null for private clusters without a public FQDN). |
| get\_credentials\_command | Command to fetch a kubeconfig that authenticates through Entra ID (requires kubelogin). |
| id | Resource ID of the AKS cluster. |
| key\_vault\_secrets\_provider\_identity | Identity of the Key Vault Secrets Store CSI driver add-on, if enabled. |
| kubelet\_identity | User-assigned identity used by the kubelet (e.g. for AcrPull). |
| name | Name of the AKS cluster. |
| node\_pool\_priorities | Priority of each user node pool (Regular or Spot). |
| node\_pool\_vm\_sizes | VM size of each user node pool. |
| node\_resource\_group | Name of the AKS-managed node resource group. |
| oidc\_issuer\_url | OIDC issuer URL, used to create federated credentials for workload identity. |
| private\_fqdn | Private FQDN of the API server (private clusters only). |
| system\_node\_pool\_vm\_size | VM size of the system node pool. |
| web\_app\_routing\_enabled | True when the managed application routing add-on is enabled. |
<!-- END_TF_DOCS -->
