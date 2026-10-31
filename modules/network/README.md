# Network module

Spoke virtual network for the platform: subnets, one NSG per subnet, and explicit egress through
either a NAT gateway or a hub firewall (see [`../hub-network`](../hub-network)).

Design choices:

- **One NSG per subnet**, with rules supplied per subnet as `azurerm_network_security_rule`
  resources, so adding a rule never rewrites the others.
- **Default outbound access is disabled** on every subnet (`default_outbound_access_enabled = false`).
  Egress must be explicit: NAT gateway, a load balancer, or a firewall via UDR.
- **NAT gateway** gives a static egress IP and avoids load balancer SNAT port exhaustion for AKS.
- **Hub integration** (optional `hub`): bidirectional peering, plus one route table that sends
  `0.0.0.0/0` to the firewall for subnets with `route_via_firewall = true`. BGP route propagation
  is disabled so on-premises routes can't bypass the firewall. A subnet uses either NAT or the
  firewall, never both.
- **Central DNS**: `private_dns_zone_links` links hub-owned private DNS zones to the spoke when a
  service needs the link directly (for example, PostgreSQL Flexible Server).
- `subnet_ids` is only available after the NSG, NAT, route table, peering and DNS link resources
  exist. This ensures consumers such as AKS are created in the right order, for example with
  `outbound_type = "userDefinedRouting"`.

## Usage

```hcl
module "network" {
  source = "../../modules/network"

  name                = "vnet-platform-prod-weu"
  resource_group_name = azurerm_resource_group.network.name
  location            = "westeurope"
  address_space       = ["10.10.0.0/16"]

  nat_gateway = { name = "ng-platform-prod-weu" }

  subnets = {
    aks_nodes = {
      name                = "snet-aks-nodes"
      address_prefixes    = ["10.10.0.0/22"]
      nat_gateway_enabled = true
    }
    postgres = {
      name             = "snet-postgres"
      address_prefixes = ["10.10.8.0/24"]
      delegation = {
        name    = "postgres"
        service = "Microsoft.DBforPostgreSQL/flexibleServers"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}
```

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name`, `resource_group_name`, `location` | Placement | required |
| `address_space` | VNet CIDRs | required |
| `dns_servers` | Custom DNS (e.g. hub resolver) | `[]` |
| `subnets` | Map of subnets with optional delegation, service endpoints, NAT or firewall routing, and NSG rules | required |
| `nat_gateway` | `{ name, idle_timeout_in_minutes, zones }` or `null` | `null` |
| `hub` | `{ virtual_network_id, firewall_private_ip }` or `null` | `null` |
| `private_dns_zone_links` | Hub private DNS zone IDs to link to the spoke | `{}` |
| `tags` | Tags | `{}` |

Hub-and-spoke usage (set `dns_servers` to the firewall so spokes use its DNS proxy):

```hcl
  dns_servers = [module.hub.firewall_private_ip]
  hub = {
    virtual_network_id  = module.hub.virtual_network_id
    firewall_private_ip = module.hub.firewall_private_ip
  }

  subnets = {
    aks_nodes = {
      name               = "snet-aks-nodes"
      address_prefixes   = ["10.10.0.0/22"]
      route_via_firewall = true
    }
  }
```

Peering to the hub requires permission to create peerings on the hub VNet as well.

## Outputs

`virtual_network_id`, `virtual_network_name`, `subnet_ids`, `route_table_id`,
`network_security_group_ids`, `nat_gateway_id`, `nat_gateway_public_ip`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| address\_space | Address space of the virtual network. | `list(string)` | n/a | yes |
| dns\_servers | Custom DNS servers (e.g. a hub DNS resolver). Empty uses Azure-provided DNS. | `list(string)` | `[]` | no |
| hub | Hub integration. Creates peerings in both directions (the hub is assumed to be in the same subscription) and a route table that sends 0.0.0.0/0 to the firewall for subnets with `route_via_firewall = true`. Null creates a standalone VNet. | ```object({ virtual_network_id = string firewall_private_ip = string })``` | `null` | no |
| location | Azure region. | `string` | n/a | yes |
| name | Name of the virtual network (e.g. vnet-platform-prod-weu). | `string` | n/a | yes |
| nat\_gateway | NAT gateway for deterministic, SNAT-exhaustion-free egress. Subnets opt in with `nat_gateway_enabled = true`. Set to null to skip creating it. | ```object({ name = string idle_timeout_in_minutes = optional(number, 4) zones = optional(list(string), []) })``` | `null` | no |
| private\_dns\_zone\_links | Existing private DNS zone IDs (typically the hub's central zones) to link to this VNet, keyed by a static name. | `map(string)` | `{}` | no |
| resource\_group\_name | Name of an existing resource group to deploy into. | `string` | n/a | yes |
| subnets | Subnets to create, keyed by a short logical name. Each subnet gets its own NSG unless `nsg_enabled = false`. `security_rules` is keyed by rule name. | ```map(object({ name = string address_prefixes = list(string) nat_gateway_enabled = optional(bool, false) route_via_firewall = optional(bool, false) nsg_enabled = optional(bool, true) service_endpoints = optional(list(string), []) private_endpoint_network_policies = optional(string, "Enabled") delegation = optional(object({ name = string service = string actions = list(string) })) security_rules = optional(map(object({ priority = number direction = string access = string protocol = string source_port_range = optional(string, "*") destination_port_range = optional(string) destination_port_ranges = optional(list(string)) source_address_prefix = optional(string) source_address_prefixes = optional(list(string)) destination_address_prefix = optional(string) destination_address_prefixes = optional(list(string)) description = optional(string) })), {}) }))``` | n/a | yes |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| nat\_gateway\_id | ID of the NAT gateway, if created. |
| nat\_gateway\_public\_ip | Egress public IP of the NAT gateway, if created. Useful for allow-listing on third-party services. |
| network\_security\_group\_ids | NSG IDs keyed by the logical subnet key. |
| route\_table\_id | ID of the firewall route table, if hub integration is enabled. |
| subnet\_ids | Subnet IDs keyed by the logical subnet key. Available only once NSG, egress, peering and DNS wiring exists. |
| virtual\_network\_id | ID of the virtual network. |
| virtual\_network\_name | Name of the virtual network. |
<!-- END_TF_DOCS -->
