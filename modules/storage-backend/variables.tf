variable "storage_account_name" {
  description = "Globally unique storage account name (3-24 lowercase letters and digits)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase letters and digits."
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

variable "account_replication_type" {
  description = "Replication. ZRS survives a zone outage; GZRS additionally replicates to the paired region."
  type        = string
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "RAGRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of LRS, ZRS, GRS, RAGRS, GZRS, RAGZRS."
  }
}

variable "container_names" {
  description = "Blob containers to create for state (e.g. one per environment or stack)."
  type        = list(string)
  default     = ["tfstate"]

  validation {
    condition     = length(var.container_names) > 0 && alltrue([for c in var.container_names : can(regex("^[a-z0-9](?:[a-z0-9]|-[a-z0-9]){2,62}$", c))])
    error_message = "Provide at least one container; names must be 3-63 lowercase letters, digits and single hyphens."
  }
}

variable "blob_soft_delete_retention_days" {
  description = "Days deleted or overwritten state blobs remain recoverable."
  type        = number
  default     = 30

  validation {
    condition     = var.blob_soft_delete_retention_days >= 1 && var.blob_soft_delete_retention_days <= 365
    error_message = "blob_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "container_soft_delete_retention_days" {
  description = "Days deleted containers remain recoverable."
  type        = number
  default     = 30

  validation {
    condition     = var.container_soft_delete_retention_days >= 1 && var.container_soft_delete_retention_days <= 365
    error_message = "container_soft_delete_retention_days must be between 1 and 365."
  }
}

variable "network_access" {
  description = <<-EOT
    Data plane network access. Public access is enabled but defaults to deny, so only the listed
    IPs, subnets and trusted Azure services can read state. Add your CI runner egress IPs here, or
    set `public_network_access = "Disabled"` and use a private endpoint.
  EOT
  type = object({
    public_network_access = optional(string, "Enabled")
    default_action        = optional(string, "Deny")
    ip_rules              = optional(list(string), [])
    subnet_ids            = optional(list(string), [])
  })
  default = {}

  validation {
    condition     = contains(["Enabled", "Disabled"], var.network_access.public_network_access) && contains(["Allow", "Deny"], var.network_access.default_action)
    error_message = "public_network_access must be Enabled/Disabled and default_action must be Allow/Deny."
  }
}

variable "state_contributors" {
  description = "Principals (CI identities, platform engineers group) granted Storage Blob Data Contributor, keyed by a static name."
  type = map(object({
    principal_id   = string
    principal_type = optional(string, "ServicePrincipal")
  }))
  default = {}
}

variable "log_analytics_workspace" {
  description = "Send blob audit logs to Log Analytics. Null disables diagnostics."
  type = object({
    id = string
  })
  default = null
}

variable "delete_lock_enabled" {
  description = "Add a CanNotDelete management lock on the storage account."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}
