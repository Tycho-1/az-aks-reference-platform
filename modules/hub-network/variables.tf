variable "name" {
  description = "Name of the hub virtual network (e.g. vnet-hub-prod-weu)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of an existing resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "address_space" {
  description = "Address space of the hub VNet."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "address_space must contain at least one valid CIDR block."
  }
}

variable "firewall" {
  description = <<-EOT
    Azure Firewall. Premium adds TLS inspection and signature-based IDPS (recommended for
    regulated workloads). `subnet_address_prefix` must be at least a /26.
  EOT
  type = object({
    name                  = string
    subnet_address_prefix = string
    sku_tier              = optional(string, "Standard")
    zones                 = optional(list(string), ["1", "2", "3"])
    threat_intel_mode     = optional(string, "Deny")
    idps_mode             = optional(string, "Deny")
  })

  validation {
    condition     = contains(["Standard", "Premium"], var.firewall.sku_tier)
    error_message = "firewall.sku_tier must be Standard or Premium (Basic lacks DNS proxy and threat intel deny)."
  }

  validation {
    condition     = can(cidrhost(var.firewall.subnet_address_prefix, 0)) && tonumber(split("/", var.firewall.subnet_address_prefix)[1]) <= 26
    error_message = "firewall.subnet_address_prefix must be a valid CIDR of /26 or larger."
  }

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall.threat_intel_mode) && contains(["Off", "Alert", "Deny"], var.firewall.idps_mode)
    error_message = "threat_intel_mode and idps_mode must be Off, Alert or Deny."
  }
}

variable "additional_subnets" {
  description = "Other hub subnets keyed by logical name. Use `bastion` for Azure Bastion and `vpn_gateway` for GatewaySubnet; Azure fixes those names."
  type = map(object({
    name             = string
    address_prefixes = list(string)
  }))
  default = {}
}

variable "bastion" {
  description = <<-EOT
    Azure Bastion in the hub for operator access to private spokes (jump host for kubectl, Terraform
    runners, or VMs). Null disables Bastion. `subnet_address_prefix` must be at least /26 and must
    not overlap the firewall subnet.
  EOT
  type = object({
    name                  = string
    subnet_address_prefix = string
    sku                   = optional(string, "Standard")
    scale_units           = optional(number, 2)
  })
  default = null

  validation {
    condition     = var.bastion == null || contains(["Basic", "Standard", "Premium"], var.bastion.sku)
    error_message = "bastion.sku must be Basic, Standard or Premium."
  }

  validation {
    condition = var.bastion == null || (
      can(cidrhost(var.bastion.subnet_address_prefix, 0)) && tonumber(split("/", var.bastion.subnet_address_prefix)[1]) <= 26
    )
    error_message = "bastion.subnet_address_prefix must be a valid CIDR of /26 or larger."
  }
}

variable "vpn_gateway" {
  description = <<-EOT
    Point-to-site VPN gateway in the hub so a laptop can join the VNet and reach private spokes
    (for example a private AKS API). Null, the default, creates nothing. Creates `GatewaySubnet`,
    a Standard public IP, and a route-based gateway with Microsoft Entra authentication over
    OpenVPN. `subnet_address_prefix` must be at least /27, must sit inside the hub address space,
    and must not overlap the firewall or Bastion subnets. Do not also pass a subnet named
    GatewaySubnet in `additional_subnets`. `client_address_space` is the pool assigned to VPN
    clients and must not overlap the hub, spokes, or Kubernetes pod and service CIDRs.
    `tenant_id` is the Entra tenant the Azure VPN Client signs in to. The gateway does not
    publish the hub private DNS zones to clients; kubectl still needs a resolver or a hosts
    entry for `privatelink.*.azmk8s.io`. VpnGw1 (the default) is non-zonal and bills per hour.
    AZ SKUs require `zones`.
  EOT
  type = object({
    name                  = string
    subnet_address_prefix = string
    client_address_space  = list(string)
    tenant_id             = string
    sku                   = optional(string, "VpnGw1")
    generation            = optional(string, "Generation1")
    zones                 = optional(list(string), [])
    aad_audience          = optional(string, "c632b3df-fb67-4d84-bdcf-b95ad541b5c8")
  })
  default = null

  validation {
    condition = var.vpn_gateway == null || contains(
      ["VpnGw1", "VpnGw2", "VpnGw3", "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ"],
      var.vpn_gateway.sku,
    )
    error_message = "vpn_gateway.sku must be VpnGw1, VpnGw2, VpnGw3, or one of the AZ variants. Basic cannot do Entra OpenVPN."
  }

  validation {
    condition     = var.vpn_gateway == null || contains(["Generation1", "Generation2"], var.vpn_gateway.generation)
    error_message = "vpn_gateway.generation must be Generation1 or Generation2."
  }

  validation {
    condition = var.vpn_gateway == null || (
      can(cidrhost(var.vpn_gateway.subnet_address_prefix, 0)) &&
      tonumber(split("/", var.vpn_gateway.subnet_address_prefix)[1]) <= 27
    )
    error_message = "vpn_gateway.subnet_address_prefix must be a valid CIDR of /27 or larger."
  }

  validation {
    condition = var.vpn_gateway == null || (
      length(var.vpn_gateway.client_address_space) > 0 &&
      alltrue([for cidr in var.vpn_gateway.client_address_space : can(cidrhost(cidr, 0))])
    )
    error_message = "vpn_gateway.client_address_space must contain at least one valid CIDR."
  }

  validation {
    condition     = var.vpn_gateway == null || can(regex("^[0-9a-fA-F-]{36}$", var.vpn_gateway.tenant_id))
    error_message = "vpn_gateway.tenant_id must be an Entra tenant GUID."
  }

  validation {
    condition = var.vpn_gateway == null || (
      endswith(var.vpn_gateway.sku, "AZ") == (length(var.vpn_gateway.zones) > 0)
    )
    error_message = "AZ VPN SKUs require zones. Non-AZ SKUs must leave zones empty."
  }
}

variable "private_dns_zones" {
  description = <<-EOT
    Central private DNS zones hosted in the hub and linked to the hub VNet. Spokes resolve them
    through the firewall DNS proxy. Keyed by a static logical name.
  EOT
  type        = map(string)
  default = {
    acr       = "privatelink.azurecr.io"
    key_vault = "privatelink.vaultcore.azure.net"
    blob      = "privatelink.blob.core.windows.net"
  }
}

variable "aks_egress" {
  description = <<-EOT
    Firewall rules that let AKS clusters in the spokes reach their required endpoints.
    `source_addresses` are the node subnet CIDRs. `additional_fqdns` extends the application
    allow-list (e.g. your Git host or upstream registries). Null skips the rule collection group.
  EOT
  type = object({
    source_addresses = list(string)
    additional_fqdns = optional(list(string), [])
  })
  default = null
}

variable "additional_network_rules" {
  description = <<-EOT
    Extra allow rules for spoke egress keyed by rule name, e.g. PostgreSQL Entra authentication
    (destination service tag AzureActiveDirectory, TCP 443).
  EOT
  type = map(object({
    source_addresses      = list(string)
    destination_addresses = list(string)
    destination_ports     = list(string)
    protocols             = optional(list(string), ["TCP"])
  }))
  default = {}
}

variable "log_analytics_workspace" {
  description = "Send firewall logs (resource-specific tables) and metrics to Log Analytics. Null disables diagnostics."
  type = object({
    id = string
  })
  default = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
