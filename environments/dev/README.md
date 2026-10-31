# Dev environment

Lightweight Azure platform for **development and learning**: one spoke VNet, NAT gateway egress, a
public API server (with an IP allow-list), and AKS. There is no hub, no Azure Firewall, and no
customer-managed keys.

`terraform.tfvars.example` is the profile verified in **North Europe** on 2026-10-23: Kubernetes
**1.36** (the cluster reported 1.36.4), zone **2**, PostgreSQL off. Both pools are
`Standard_D2s_v3` with a Managed disk and **Regular** priority, set in `main.tf`. Spot `Standard_B2s`
had no capacity in that region, and the Dds_v5 quota family was 0.

Use [`../prod`](../prod) when you need the full regulated pattern (private cluster, firewall egress,
CMK, alerting, Flux GitOps).

## What gets deployed

| Layer | Resources |
|-------|-----------|
| Network | VNet, NAT gateway, subnets for AKS nodes and private endpoints; optional delegated subnet for PostgreSQL |
| Observability | Log Analytics (30-day retention), Azure Monitor workspace (managed Prometheus) |
| AKS | Entra RBAC (Azure RBAC for Kubernetes, local accounts off), workload identity, CNI Overlay + Cilium, system and `apps` pools (`Standard_D2s_v3`, Regular, Managed disk) |
| Data (optional) | Private PostgreSQL Flexible Server (`B_Standard_B2s`, no zone-redundant HA) when `postgres_enabled = true` |

Resource groups are split by lifecycle: `rg-<workload>-dev-<region>-network`, `-aks`, `-data`, `-ops`.

## Key inputs

| Variable | Purpose | Default |
|----------|---------|---------|
| `aks_admin_group_object_ids` | Entra groups with cluster-admin | required |
| `api_server_authorized_ip_ranges` | Admin/client IPs for the public API (`curl -4`); **NAT egress IP is merged automatically** for node→API traffic | `[]` (open; module may warn) |
| `postgres_enabled` | Create PostgreSQL | `false` |
| `postgres_admin_group` | Entra admin for Postgres | required if Postgres is enabled |
| `kubernetes_version` | AKS minor version | `1.37` |
| `node_availability_zones` | Zones for system and `apps` pools (set in tfvars when region limits AZs) | `["1", "2", "3"]` |
| `environment` | Name suffix and sizing profile (`dev`, `test`, `prod`) | `dev` |

The `environment` input changes naming and scale (node counts, SKU tier, backup retention). The
default **`dev`** profile uses smaller pools and AKS **Free** tier. Setting `environment = "prod"`
in this same root turns on production-like sizing inside the simple topology (used by
`tests/dev.tftest.hcl`); for real production, use the [`prod`](../prod) root instead.

## Deploy

Prerequisites: Terraform ≥ 1.11.1, Azure CLI, remote state from
[`modules/storage-backend/examples/bootstrap`](../../modules/storage-backend/examples/bootstrap),
and permission to assign roles on the subscription.

```sh
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars   # group IDs, IPs, optional Postgres
export ARM_SUBSCRIPTION_ID=<subscription-id>
terraform init -backend-config=backend.hcl
terraform plan -out tfplan
terraform apply tfplan
```

Confirm `kubernetes_version` is offered in your region:

```sh
az aks get-versions --location northeurope -o table
```

## After apply

```sh
sudo az aks install-cli   # kubectl and kubelogin, once per machine
terraform output aks_get_credentials
# Run the printed command, then:
kubelogin convert-kubeconfig -l azurecli
```

Local accounts are disabled and Azure RBAC for Kubernetes is on. **Contributor** or **Owner** on
the subscription does not grant `kubectl`. After each new cluster, assign **Azure Kubernetes
Service RBAC Cluster Admin** to the Entra group in `aks_admin_group_object_ids`, scoped to that
cluster, then sign in again:

```sh
az role assignment create \
  --role "Azure Kubernetes Service RBAC Cluster Admin" \
  --assignee-object-id "<group-object-id>" \
  --assignee-principal-type Group \
  --scope "$(az aks show -g rg-platform-dev-neu-aks -n aks-platform-dev-neu --query id -o tsv)"
az login --use-device-code
kubectl get nodes
```

The assignee is the Entra group (or your user). The scope is the cluster resource id from
`az aks show`. Destroying the cluster deletes that assignment; the group membership stays. A
replacement cluster needs the role created again, even when the scope string looks the same.

## Optional PostgreSQL

```hcl
postgres_enabled = true
postgres_admin_group = {
  object_id    = "<entra-group-object-id>"
  display_name = "sg-platform-postgres-admins"
}
```

When disabled, `postgres_fqdn` is `null` and you avoid database cost—useful for AKS-only sandboxes.

## Tests

```sh
terraform init -backend=false
terraform test
```

Plan-only runs use mocked providers; no Azure credentials required.

## Related

- Platform overview: [repository README](../../README.md)
- Full production stack: [`../prod`](../prod)
