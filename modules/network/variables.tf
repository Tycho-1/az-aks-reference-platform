variable "name" {
  description = "Name of the virtual network (e.g. vnet-platform-prod-weu)."
  type        = string
}

variable "resource_group_name" {
  description = "Name of an existing resource group to deploy into."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "address_space" {
  description = "Address space of the virtual network."
  type        = list(string)

  validation {
    condition     = length(var.address_space) > 0 && alltrue([for cidr in var.address_space : can(cidrhost(cidr, 0))])
    error_message = "address_space must contain at least one valid CIDR block."
  }
}

variable "dns_servers" {
  description = "Custom DNS servers (e.g. a hub DNS resolver). Empty uses Azure-provided DNS."
  type        = list(string)
  default     = []
}

variable "subnets" {
  description = <<-EOT
    Subnets to create, keyed by a short logical name. Each subnet gets its own NSG unless
    `nsg_enabled = false`. `security_rules` is keyed by rule name.
  EOT
  type = map(object({
    name                              = string
    address_prefixes                  = list(string)
    nat_gateway_enabled               = optional(bool, false)
    route_via_firewall                = optional(bool, false)
    nsg_enabled                       = optional(bool, true)
    service_endpoints                 = optional(list(string), [])
    private_endpoint_network_policies = optional(string, "Enabled")
    delegation = optional(object({
      name    = string
      service = string
      actions = list(string)
    }))
    security_rules = optional(map(object({
      priority                     = number
      direction                    = string
      access                       = string
      protocol                     = string
      source_port_range            = optional(string, "*")
      destination_port_range       = optional(string)
      destination_port_ranges      = optional(list(string))
      source_address_prefix        = optional(string)
      source_address_prefixes      = optional(list(string))
      destination_address_prefix   = optional(string)
      destination_address_prefixes = optional(list(string))
      description                  = optional(string)
    })), {})
  }))

  validation {
    condition = alltrue([
      for s in values(var.subnets) : alltrue([for cidr in s.address_prefixes : can(cidrhost(cidr, 0))])
    ])
    error_message = "Every subnet address prefix must be a valid CIDR block."
  }

  validation {
    condition = alltrue(flatten([
      for s in values(var.subnets) : [
        for r in values(s.security_rules) : r.priority >= 100 && r.priority <= 4096 && contains(["Inbound", "Outbound"], r.direction) && contains(["Allow", "Deny"], r.access)
      ]
    ]))
    error_message = "Security rules need a priority between 100 and 4096, direction Inbound/Outbound and access Allow/Deny."
  }

  validation {
    condition     = alltrue([for s in values(var.subnets) : !(s.nat_gateway_enabled && s.route_via_firewall)])
    error_message = "A subnet cannot use both the NAT gateway and the firewall route; pick one egress path."
  }
}

variable "hub" {
  description = <<-EOT
    Hub integration. Creates peerings in both directions (the hub is assumed to be in the same
    subscription) and a route table that sends 0.0.0.0/0 to the firewall for subnets with
    `route_via_firewall = true`. Null creates a standalone VNet.
  EOT
  type = object({
    virtual_network_id  = string
    firewall_private_ip = string
  })
  default = null
}

variable "private_dns_zone_links" {
  description = "Existing private DNS zone IDs (typically the hub's central zones) to link to this VNet, keyed by a static name."
  type        = map(string)
  default     = {}
}

variable "nat_gateway" {
  description = <<-EOT
    NAT gateway for deterministic, SNAT-exhaustion-free egress. Subnets opt in with
    `nat_gateway_enabled = true`. Set to null to skip creating it.
  EOT
  type = object({
    name                    = string
    idle_timeout_in_minutes = optional(number, 4)
    zones                   = optional(list(string), [])
  })
  default = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
