variable "name" {
  description = "Globally unique Key Vault name (3-24 characters)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$", var.name))
    error_message = "Key Vault name must be 3-24 alphanumerics or hyphens, starting with a letter."
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

variable "sku_name" {
  description = "premium enables HSM-backed keys (RSA-HSM), recommended for customer-managed keys."
  type        = string
  default     = "premium"

  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be standard or premium."
  }
}

variable "soft_delete_retention_days" {
  description = "Soft delete retention (7-90). Purge protection is always on, as CMK scenarios require it."
  type        = number
  default     = 90

  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90."
  }
}

variable "allowed_ip_ranges" {
  description = <<-EOT
    Public IPs/CIDRs allowed to reach the data plane (e.g. the Terraform runner). Empty disables
    public network access entirely; Terraform must then run from a network with private endpoint access.
    Trusted Azure services (disk encryption sets, ACR, PostgreSQL) are always allowed.
  EOT
  type        = list(string)
  default     = []
}

variable "private_endpoint" {
  description = <<-EOT
    Private endpoint for the vault. `private_dns_zone_id` should be a privatelink.vaultcore.azure.net
    zone. Set `location` when the subnet's VNet is in a different region than the vault.
  EOT
  type = object({
    subnet_id           = string
    private_dns_zone_id = string
    location            = optional(string)
  })
  default = null
}

variable "keys" {
  description = <<-EOT
    Keys keyed by name. Keys rotate automatically after `rotate_after` (ISO 8601 duration) and never
    expire, because consumers pinned to a version (e.g. AKS KMS) would break on expiry.
  EOT
  type = map(object({
    key_type     = optional(string, "RSA-HSM")
    key_size     = optional(number, 3072)
    key_opts     = optional(list(string), ["wrapKey", "unwrapKey"])
    rotate_after = optional(string, "P365D")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in values(var.keys) : contains(["RSA", "RSA-HSM"], k.key_type) && contains([2048, 3072, 4096], k.key_size)])
    error_message = "Keys must be RSA or RSA-HSM with size 2048, 3072 or 4096 (the types supported by Azure CMK integrations)."
  }
}

variable "deployer_crypto_officer_enabled" {
  description = "Grant the identity running Terraform Key Vault Crypto Officer so it can manage the keys."
  type        = bool
  default     = true
}

variable "role_assignments" {
  description = "Additional data plane role assignments keyed by a static name."
  type = map(object({
    principal_id         = string
    role_definition_name = string
    principal_type       = optional(string, "ServicePrincipal")
  }))
  default = {}
}

variable "log_analytics_workspace" {
  description = "Send audit logs to Log Analytics. Null disables diagnostics."
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
