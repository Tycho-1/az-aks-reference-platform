variable "name" {
  description = "Globally unique registry name (5-50 alphanumerics)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]{5,50}$", var.name))
    error_message = "Registry name must be 5-50 alphanumeric characters."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "sku" {
  description = "Premium is required for private endpoints, zone redundancy, geo-replication, retention and CMK."
  type        = string
  default     = "Premium"

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be Basic, Standard or Premium."
  }
}

variable "allowed_ip_ranges" {
  description = "Public CIDRs allowed to reach the registry (e.g. hosted CI runners). Empty disables public network access."
  type        = list(string)
  default     = []
}

variable "private_endpoint" {
  description = <<-EOT
    Private endpoint for the registry. `private_dns_zone_id` should be a privatelink.azurecr.io zone.
    Set `location` when the subnet's VNet is in a different region than the registry.
  EOT
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
    location            = optional(string)
  })
  default = null
}

variable "georeplications" {
  description = "Additional replica regions keyed by location, for regional resilience and pull locality."
  type = map(object({
    zone_redundancy_enabled = optional(bool, true)
  }))
  default = {}
}

variable "untagged_manifest_retention_days" {
  description = "Delete untagged manifests after this many days. Null disables the retention policy."
  type        = number
  default     = 7
}

variable "customer_managed_key" {
  description = <<-EOT
    Encrypt registry content with a Key Vault key. Only possible at creation time. Use a
    versionless key ID so ACR picks up rotated key versions automatically.
  EOT
  type = object({
    key_vault_id     = string
    key_vault_key_id = string
  })
  default = null
}

variable "role_assignments" {
  description = "Registry role assignments keyed by a static name, e.g. AcrPush for a CI identity."
  type = map(object({
    principal_id         = string
    role_definition_name = string
    principal_type       = optional(string, "ServicePrincipal")
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.role_assignments) : contains(["AcrPull", "AcrPush", "AcrDelete", "Reader", "Contributor"], r.role_definition_name)])
    error_message = "Unsupported registry role."
  }
}

variable "log_analytics_workspace" {
  description = "Send registry logs and metrics to Log Analytics. Null disables diagnostics."
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
