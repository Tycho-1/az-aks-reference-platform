# Prod environment

Full platform root: hub-and-spoke, Azure Firewall egress, a private AKS cluster, private ACR and
Key Vault, customer-managed keys, and alerting. PostgreSQL is on by default and can be
turned off for a short smoke test. Flux stays off until `gitops_repository_url` is set.

This is one Terraform state (`prod.tfstate`). Resource groups split the layers so a later split
into separate states (foundation, GitOps, data) does not require renaming resources.
[`../dev`](../dev) is the cheap public-API sandbox and is not a smaller copy of this topology.

The diagram in the [repository README](../../README.md#architecture) is this environment.

## Architecture

```text
Internet
   ^
   |  Azure Firewall (DNS proxy, threat intel Deny)
   |
Hub VNet 10.0.0.0/22          rg-*-connectivity
   AzureFirewallSubnet, AzureBastionSubnet
   private DNS: ACR, Key Vault, AKS, PostgreSQL
        |  peering
        v
Spoke VNet 10.10.0.0/16       rg-*-network
   snet-aks-nodes        10.10.0.0/22   UDR 0.0.0.0/0 → firewall
   snet-aks-apiserver    10.10.4.0/28   delegated to AKS (API VNet integration)
   snet-postgres         10.10.8.0/24   delegated; kept even when the server is off
   snet-private-endpoints 10.10.9.0/24  ACR + Key Vault private endpoints

AKS (private)             rg-*-aks
   system pool  Regular, Standard_D4ds_v5, min 3
   apps pool    Regular by default (Spot only via tfvars), Standard_D4ds_v5, min 3
   pods 10.244.0.0/16, services 10.245.0.0/16 (overlay; must not overlap the VNets)
   ACR Premium + CMK, sample workload identity

Key Vault (RBAC, HSM keys) rg-*-security
   primary region: aks-disk, aks-kms, acr, and postgres when the server is on
   paired region:  postgres geo-backup key only, and only when the server is on

Log Analytics, Prometheus, alerts   rg-*-ops
PostgreSQL Flexible Server          rg-*-data   (only when postgres_enabled = true)
```

Spoke DNS servers are the firewall's private IP, so names in the hub private zones resolve for
nodes and private endpoints. Node egress is `userDefinedRouting`: the default route
`0.0.0.0/0` goes to the firewall, BGP route propagation is disabled, and the policy allows the
AKS required outbound set (FQDN tag, NTP, Azure Monitor, tunnel ports) and denies the rest.
With Flux enabled, the Git host plus `charts.jetstack.io` and `quay.io` are added. With
PostgreSQL enabled, the database subnet may reach Entra ID on TCP 443 for authentication.

The API server has no public endpoint and no authorized-IP list. It is integrated into
`snet-aks-apiserver` and registered in the hub private DNS zone
`privatelink.<region>.azmk8s.io`. A laptop cannot `kubectl` it directly. Use
`az aks command invoke`, or a VM reached through Bastion. `vpn_gateway_enabled = true` adds a
point-to-site gateway for a laptop, but that tunnel still does not resolve the private API
name.

## What an apply creates

Names use `rg-<workload>-prod-<location_short>-<layer>` (default `rg-platform-prod-weu-…`).
Key Vault and ACR get a 4-character random suffix because those names are global.

| Layer | Resource group | Always created |
|-------|----------------|----------------|
| Connectivity | `connectivity` | Hub VNet, Azure Firewall Standard with no availability zones, firewall policy, Bastion, four private DNS zones, diagnostic settings |
| Network | `network` | Spoke VNet, four subnets, NSGs, route table to the firewall, peering both ways, PostgreSQL DNS link |
| Security | `security` | Primary Key Vault (private endpoint, purge protection, keys for disks, etcd, ACR) |
| Cluster | `aks` | Private AKS Standard tier, system + `apps` pools, kubelet and control-plane identities, role assignments (including AcrPull), disk encryption set, KMS, ACR Premium with private endpoint and CMK, sample-API user-assigned identity and federated credential, managed NGINX routing |
| Operations | `ops` | Log Analytics (90-day retention), Azure Monitor workspace, action group, metric and Prometheus alerts, service-health alert for the primary and paired regions |
| Data | `data` | The resource group is always created. The server is not (see below). |

AKS also creates its own node resource group (`MC_…`) outside this list. That group is deleted
with the cluster.

A full apply is on the order of **100 resources**. [`../dev`](../dev) is nearer 30 because it
has no hub, firewall, private DNS, private endpoints, CMK, or alert set. Most of the prod count
is role assignments, DNS links, firewall rules, and diagnostics. The hourly cost is dominated
by **Azure Firewall**, not by the number of resources.

### Turned off unless you set them

| Input | Default | When set |
|-------|---------|----------|
| `postgres_enabled` | `true` | `false` skips the Flexible Server and the paired-region Key Vault. The PostgreSQL subnet, private DNS zone, and Entra firewall rule stay, so enabling the server later does not rebuild the network. |
| `gitops_repository_url` | `null` | HTTPS URL installs the Flux extension (`gitops/infrastructure/controllers`, then `gitops/apps/production`) and opens those FQDNs on the firewall. |
| `monthly_budget` | `null` | `{ amount, start_date }` adds a subscription budget alert (80%, 100%, and forecast). `start_date` is the first of a month, `YYYY-MM-01T00:00:00Z`. |
| `apps_node_pool_priority` | `Regular` | `Spot` is for a short smoke test of the **apps** pool only. The system pool stays on-demand; AKS does not allow Spot there. Spot nodes are tainted `kubernetes.azure.com/scalesetpriority=spot:NoSchedule` and can be evicted. |
| `acr_allowed_ip_ranges` | `[]` | Public IPs of hosted CI runners that push images. Empty keeps the registry private-only. |
| `host_encryption_enabled` | `false` | Encrypts node temp disks. Requires the `EncryptionAtHost` feature on the subscription. |
| `vpn_gateway_enabled` | `false` | `true` adds a VpnGw1 point-to-site gateway (`GatewaySubnet` `10.0.0.128/26` on the default hub, client pool `172.16.201.0/24`). It bills for every hour it exists. CI, Flux, and `az aks command invoke` do not need it. |

PostgreSQL, when enabled, is `GP_Standard_D4ds_v5` with zone-redundant high availability,
geo-redundant backups, and a customer-managed key in both the primary region and
`paired_location`. `paired_location` is the [Azure paired region](https://learn.microsoft.com/azure/reliability/regions-paired)
(West Europe for a North Europe primary). It is disaster recovery for backups, not cluster
failover. The live server stays in `location`. `postgres_admin_group` is required only when
the server is on.

### Node pools

| Pool | Size | Count | Priority | Disk |
|------|------|-------|----------|------|
| `system` | `system_node_pool_vm_size` | `system_node_pool_min_count`–5 | Regular (not configurable) | `system_node_pool_os_disk_type` |
| `apps` | `apps_node_pool_vm_size` | `apps_node_pool_min_count`–`apps_node_pool_max_count` | `apps_node_pool_priority` | `apps_node_pool_os_disk_type` |

Defaults are `Standard_D4ds_v5`, ephemeral disk, system minimum 3, apps 3–10 Regular. The system pool is tainted `CriticalAddonsOnly`. AKS does not allow Spot on it. `Standard_D2s_v3` needs `os_disk_type = "Managed"`.

Both pools use `node_availability_zones` (default `["1", "2", "3"]`). Set a shorter list in
tfvars when the region or SKU does not offer every zone.

## Key inputs

Copy `terraform.tfvars.example` to `terraform.tfvars` (not committed).

| Variable | Purpose | Default |
|----------|---------|---------|
| `workload`, `location`, `location_short` | Names and primary region | `platform`, `westeurope`, `weu` |
| `paired_location` | Region of the PostgreSQL geo-backup key | `northeurope` |
| `hub_address_space`, `spoke_address_space` | VNet CIDRs; must not overlap each other or the pod/service CIDRs | `10.0.0.0/22`, `10.10.0.0/16` |
| `vpn_gateway_enabled` | Point-to-site VPN in the hub for laptop `kubectl`. Off in production. | `false` |
| `kubernetes_version` | AKS **minor** only (`1.37`) | `1.37` |
| `aks_admin_group_object_ids` | Entra groups with cluster-admin. Required: local accounts are disabled. | — |
| `operator_ip_ranges` | Your public IP, so Terraform can create keys in Key Vault. Empty when Terraform runs inside the spoke. | `[]` |
| `alert_email_receivers` | On-call addresses, keyed by a static name | — |
| `owner` | Tag | `platform-team` |

`terraform.tfvars.example` records the smoke test, not the variable defaults in the table above. It was applied in
North Europe on 2026-10-30 and destroyed the same day: `northeurope` / `neu`, Kubernetes
`1.36`, one zone, `Standard_D2s_v3` with Managed disks, a Spot apps pool of 1–2 nodes,
PostgreSQL off, Flux off, and no budget alert. The firewall has no availability zones
because `network.tf` sets `zones = []`. The example still uses a placeholder Entra group
and the documentation address `203.0.113.10/32`; replace both before an apply. The larger
West Europe layout is commented in the same file. A smoke test still bills the firewall
for every hour it exists.

## Deploy

Prerequisites: Terraform ≥ 1.11, Azure CLI, an Entra group you belong to, and permission to
create resources and role assignments. Remote state comes from
[`modules/storage-backend/examples/bootstrap`](../../modules/storage-backend/examples/bootstrap).
For a local-state trial, `terraform init -backend=false` instead of the backend config below.

```sh
cp backend.hcl.example backend.hcl          # fill in the state storage account
cp terraform.tfvars.example terraform.tfvars
export ARM_SUBSCRIPTION_ID=<subscription-id>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```

Confirm the minor version exists in the region before apply:

```sh
az aks get-versions --location westeurope -o table
```

Key creation from a laptop needs `operator_ip_ranges` set to that machine's public IPv4
as a `/32`. The API server stays private either way. A pipeline apply should run from a
self-hosted runner in the spoke, or from a VM reached via Bastion, with
`operator_ip_ranges` empty. See `terraform output operator_access`.

## After apply

```sh
terraform output aks_command_invoke_example
# The API server is private. Example:
az aks command invoke -g rg-platform-prod-weu-aks -n aks-platform-prod-weu --command "kubectl get nodes"

terraform output egress_public_ip          # firewall public IP; all spoke egress
terraform output acr_login_server
terraform output postgres_fqdn             # null when postgres_enabled is false
terraform output sample_api_workload_identity
```

Bastion is `bas-hub-prod-<location_short>` in the connectivity resource group. Clipboard and
file copy are disabled.

## Tests

```sh
terraform init -backend=false
terraform test
```

Plan-only, mocked providers, no Azure credentials. The suite checks the full stack, a Spot
apps pool, `postgres_enabled = false`, and `vpn_gateway_enabled = true`.

## Related

- [Repository architecture](../../README.md#architecture)
- [Hub-and-spoke decision](../../docs/adr/0002-hub-and-spoke-with-azure-firewall.md)
- [Private endpoints and central DNS](../../docs/adr/0004-private-endpoints-and-central-dns.md)
- [Customer-managed keys](../../docs/adr/0003-customer-managed-keys-opt-in.md)
- [Terraform stops at the cluster boundary](../../docs/adr/0005-terraform-stops-at-the-cluster-boundary.md)
- Dev sandbox: [`../dev`](../dev)
