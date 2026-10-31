# Hub network module

Connectivity hub for a [hub-and-spoke topology](https://learn.microsoft.com/azure/architecture/networking/architecture/hub-spoke):
hub VNet, zone-redundant Azure Firewall with a firewall policy, and the central private DNS
zones that spokes resolve through the firewall DNS proxy.

Spokes are created with [`../network`](../network), which peers to the hub, routes `0.0.0.0/0`
to the firewall, and uses the firewall as DNS server.

## What you get by default

| Area | Default |
|------|---------|
| Firewall | `Standard` tier across zones 1-3, threat intelligence in `Deny` mode, Premium adds IDPS (`Deny`) |
| Policy | DNS proxy enabled; default deny, with no allow rules until you add them |
| AKS egress | Optional rule collection group for [AKS required outbound traffic](https://learn.microsoft.com/azure/aks/outbound-rules-control-egress): `AzureKubernetesService` FQDN tag, NTP, Azure Monitor, tunnel ports |
| DNS | Central private DNS zones (`acr`, `key_vault`, `blob` by default) linked to the hub |
| Bastion | Optional `bastion` input: `AzureBastionSubnet`, host with clipboard and file copy disabled |
| VPN | Optional `vpn_gateway` input. Null (the default) creates nothing. When set: `GatewaySubnet`, a VpnGw1 point-to-site gateway, Entra ID sign-in |
| Logs | Firewall, Bastion, and VPN logs to resource-specific tables in Log Analytics |

## Usage

```hcl
module "hub" {
  source = "../../modules/hub-network"

  name                = "vnet-hub-prod-weu"
  resource_group_name = azurerm_resource_group.connectivity.name
  location            = "westeurope"
  address_space       = ["10.0.0.0/22"]

  firewall = {
    name                  = "afw-hub-prod-weu"
    subnet_address_prefix = "10.0.0.0/26"
  }

  aks_egress = {
    source_addresses = ["10.10.0.0/22"]
    additional_fqdns = ["github.com", "*.githubusercontent.com"]
  }

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
}
```

## Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `address_space` | Hub VNet CIDRs | required |
| `firewall` | `{ name, subnet_address_prefix, sku_tier, zones, threat_intel_mode, idps_mode }` | `Standard`, 3 zones |
| `bastion` | `{ name, subnet_address_prefix, sku, scale_units }` or `null` | `null` |
| `vpn_gateway` | Point-to-site VPN, or `null` to leave it out | `null` |
| `additional_subnets` | Extra hub subnets. Do not use this for `GatewaySubnet`; pass `vpn_gateway` instead | `{}` |
| `private_dns_zones` | Central zones keyed by logical name | ACR, Key Vault, blob |
| `aks_egress` | `{ source_addresses, additional_fqdns }` or `null` | `null` |
| `additional_network_rules` | Extra network allow rules keyed by name | `{}` |
| `log_analytics_workspace` | `{ id }` or `null` | `null` |

## Outputs

`virtual_network_id`, `virtual_network_name`, `firewall_private_ip`, `firewall_public_ip`,
`firewall_policy_id`, `private_dns_zone_ids`, `subnet_ids`, `bastion_host_id`,
`vpn_gateway_id`, `vpn_gateway_public_ip`.

## Point-to-site VPN

Leave `vpn_gateway` unset. The default is off, same as Bastion.

Set it when a laptop must open `kubectl` against a private API. Bastion only reaches virtual
machines. The gateway puts the laptop on the hub network. Pass a subnet that fits in the hub
and does not overlap the firewall (`10.0.0.0/26` in the example below) or Bastion
(`10.0.0.64/26`). `10.0.0.128/26` is the next free block of a `10.0.0.0/22` hub.

```hcl
vpn_gateway = {
  name                  = "vpng-hub-prod-weu"
  subnet_address_prefix = "10.0.0.128/26"
  client_address_space  = ["172.16.201.0/24"]
  tenant_id             = data.azurerm_client_config.current.tenant_id
}
```

Install the Azure VPN Client and sign in with Entra ID. The tunnel does not hand the laptop
the hub private DNS zones. `kubectl` still fails with `no such host` for
`privatelink.<region>.azmk8s.io` until clients use a DNS private resolver in the VNet, or a
hosts entry for that one API address. The client pool must not overlap the hub, the spokes,
or the cluster pod and service CIDRs.

`VpnGw1` bills for every hour the gateway exists, including idle hours. AZ SKUs
(`VpnGw1AZ` and up) need `zones`. Non-AZ SKUs must leave `zones` empty.

## Notes

- **Cost.** Azure Firewall is billed hourly plus per GB processed. In a real landing zone the hub
  is shared by many spokes and usually owned by a platform team. This module stands one up so the
  reference platform is self-contained.
- **Premium** is recommended for regulated workloads (TLS inspection, signature-based IDPS).
- For many spokes or multiple regions, consider Azure Virtual WAN or
  [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) hub patterns.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| additional\_network\_rules | Extra allow rules for spoke egress keyed by rule name, e.g. PostgreSQL Entra authentication (destination service tag AzureActiveDirectory, TCP 443). | ```map(object({ source_addresses = list(string) destination_addresses = list(string) destination_ports = list(string) protocols = optional(list(string), ["TCP"]) }))``` | `{}` | no |
| additional\_subnets | Other hub subnets keyed by logical name. Use `bastion` for Azure Bastion and `vpn_gateway` for GatewaySubnet; Azure fixes those names. | ```map(object({ name = string address_prefixes = list(string) }))``` | `{}` | no |
| address\_space | Address space of the hub VNet. | `list(string)` | n/a | yes |
| aks\_egress | Firewall rules that let AKS clusters in the spokes reach their required endpoints. `source_addresses` are the node subnet CIDRs. `additional_fqdns` extends the application allow-list (e.g. your Git host or upstream registries). Null skips the rule collection group. | ```object({ source_addresses = list(string) additional_fqdns = optional(list(string), []) })``` | `null` | no |
| bastion | Azure Bastion in the hub for operator access to private spokes (jump host for kubectl, Terraform runners, or VMs). Null disables Bastion. `subnet_address_prefix` must be at least /26 and must not overlap the firewall subnet. | ```object({ name = string subnet_address_prefix = string sku = optional(string, "Standard") scale_units = optional(number, 2) })``` | `null` | no |
| firewall | Azure Firewall. Premium adds TLS inspection and signature-based IDPS (recommended for regulated workloads). `subnet_address_prefix` must be at least a /26. | ```object({ name = string subnet_address_prefix = string sku_tier = optional(string, "Standard") zones = optional(list(string), ["1", "2", "3"]) threat_intel_mode = optional(string, "Deny") idps_mode = optional(string, "Deny") })``` | n/a | yes |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace | Send firewall logs (resource-specific tables) and metrics to Log Analytics. Null disables diagnostics. | ```object({ id = string })``` | `null` | no |
| name | Name of the hub virtual network (e.g. vnet-hub-prod-weu). | `string` | n/a | yes |
| private\_dns\_zones | Central private DNS zones hosted in the hub and linked to the hub VNet. Spokes resolve them through the firewall DNS proxy. Keyed by a static logical name. | `map(string)` | ```{ "acr": "privatelink.azurecr.io", "blob": "privatelink.blob.core.windows.net", "key_vault": "privatelink.vaultcore.azure.net" }``` | no |
| resource\_group\_name | Name of an existing resource group. | `string` | n/a | yes |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| vpn\_gateway | Point-to-site VPN gateway in the hub so a laptop can join the VNet and reach private spokes (for example a private AKS API). Null, the default, creates nothing. Creates `GatewaySubnet`, a Standard public IP, and a route-based gateway with Microsoft Entra authentication over OpenVPN. `subnet_address_prefix` must be at least /27, must sit inside the hub address space, and must not overlap the firewall or Bastion subnets. Do not also pass a subnet named GatewaySubnet in `additional_subnets`. `client_address_space` is the pool assigned to VPN clients and must not overlap the hub, spokes, or Kubernetes pod and service CIDRs. `tenant_id` is the Entra tenant the Azure VPN Client signs in to. The gateway does not publish the hub private DNS zones to clients; kubectl still needs a resolver or a hosts entry for `privatelink.*.azmk8s.io`. VpnGw1 (the default) is non-zonal and bills per hour. AZ SKUs require `zones`. | ```object({ name = string subnet_address_prefix = string client_address_space = list(string) tenant_id = string sku = optional(string, "VpnGw1") generation = optional(string, "Generation1") zones = optional(list(string), []) aad_audience = optional(string, "c632b3df-fb67-4d84-bdcf-b95ad541b5c8") })``` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| bastion\_host\_id | ID of the Azure Bastion host when `bastion` is set; null otherwise. |
| bastion\_host\_name | Name of the Azure Bastion host when `bastion` is set; null otherwise. |
| firewall\_id | ID of the Azure Firewall. |
| firewall\_policy\_id | ID of the firewall policy, for adding workload-specific rule collection groups. |
| firewall\_private\_ip | Private IP of the firewall: next hop for spoke default routes and DNS server for spokes. |
| firewall\_public\_ip | Egress public IP of the firewall. Allow-list this on third-party services. |
| private\_dns\_zone\_ids | Central private DNS zone IDs keyed by logical name. |
| subnet\_ids | IDs of the additional hub subnets keyed by logical name. |
| virtual\_network\_id | ID of the hub VNet. |
| virtual\_network\_name | Name of the hub VNet. |
| vpn\_gateway\_id | ID of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise. |
| vpn\_gateway\_name | Name of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise. |
| vpn\_gateway\_public\_ip | Public IP of the point-to-site VPN gateway when `vpn_gateway` is set; null otherwise. |
<!-- END_TF_DOCS -->
