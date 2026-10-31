################################################################################
# General
################################################################################

variable "name" {
  description = "Globally unique server name (e.g. psql-platform-prod-weu)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$", var.name))
    error_message = "Server name must be 3-63 lowercase letters, digits or hyphens and start/end alphanumeric."
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

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

################################################################################
# Compute, storage and version
################################################################################

variable "postgresql_version" {
  description = "Major PostgreSQL version."
  type        = string
  default     = "17"

  validation {
    condition     = contains(["14", "15", "16", "17", "18"], var.postgresql_version)
    error_message = "postgresql_version must be one of 14, 15, 16, 17 or 18."
  }
}

variable "sku_name" {
  description = "SKU in <tier>_<size> form. General Purpose (GP_) or Memory Optimized (MO_) is required for high availability."
  type        = string
  default     = "GP_Standard_D2ds_v5"

  validation {
    condition     = can(regex("^(B|GP|MO)_", var.sku_name))
    error_message = "sku_name must start with B_, GP_ or MO_."
  }
}

variable "storage_mb" {
  description = "Allocated storage in MB. With auto-grow enabled this is the starting size."
  type        = number
  default     = 65536
}

variable "auto_grow_enabled" {
  description = "Automatically grow storage before it runs out."
  type        = bool
  default     = true
}

variable "zone" {
  description = "Availability zone of the primary server."
  type        = string
  default     = "1"
}

variable "high_availability" {
  description = <<-EOT
    High availability. ZoneRedundant places a hot standby in another zone (recommended for
    production; not available on Burstable SKUs). Null disables HA.
  EOT
  type = object({
    mode                      = optional(string, "ZoneRedundant")
    standby_availability_zone = optional(string, "2")
  })
  default = {}

  validation {
    condition     = var.high_availability == null || contains(["ZoneRedundant", "SameZone"], try(var.high_availability.mode, ""))
    error_message = "high_availability.mode must be ZoneRedundant or SameZone."
  }
}

################################################################################
# Backup and maintenance
################################################################################

variable "backup_retention_days" {
  description = "Point-in-time restore window in days (7-35)."
  type        = number
  default     = 35

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 7 and 35."
  }
}

variable "geo_redundant_backup_enabled" {
  description = "Replicate backups to the paired region. Can only be set at creation time."
  type        = bool
  default     = false
}

variable "maintenance_window" {
  description = "Custom maintenance window (UTC). day_of_week: 0 = Sunday."
  type = object({
    day_of_week  = optional(number, 0)
    start_hour   = optional(number, 2)
    start_minute = optional(number, 0)
  })
  default = {}
}

################################################################################
# Networking
################################################################################

variable "delegated_subnet_id" {
  description = "Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. The server gets no public endpoint."
  type        = string
}

variable "private_dns_zone" {
  description = <<-EOT
    Private DNS. Either pass an existing zone via `id` (typical for hub-and-spoke with central DNS),
    or let the module create `<name>.private.postgres.database.azure.com` linked to `virtual_network_ids`.
  EOT
  type = object({
    id                  = optional(string)
    virtual_network_ids = optional(map(string))
  })

  validation {
    condition     = (var.private_dns_zone.id != null) != (var.private_dns_zone.virtual_network_ids != null)
    error_message = "Set exactly one of private_dns_zone.id or private_dns_zone.virtual_network_ids."
  }
}

################################################################################
# Authentication
################################################################################

variable "entra_administrator" {
  description = "Entra ID principal (preferably a group) that administers the server."
  type = object({
    object_id      = string
    principal_name = string
    principal_type = optional(string, "Group")
  })

  validation {
    condition     = contains(["Group", "ServicePrincipal", "User"], var.entra_administrator.principal_type)
    error_message = "principal_type must be Group, ServicePrincipal or User."
  }
}

variable "password_auth_enabled" {
  description = "Allow PostgreSQL password authentication in addition to Entra ID. Keep false unless a client cannot use Entra tokens."
  type        = bool
  default     = false
}

variable "administrator_login" {
  description = "Local administrator login. Only used when password_auth_enabled = true."
  type        = string
  default     = null
}

variable "administrator_password" {
  description = "Local administrator password. Ephemeral: it is passed through a write-only argument and never stored in state."
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
}

variable "administrator_password_version" {
  description = "Increment to rotate administrator_password (write-only values are not diffed)."
  type        = number
  default     = 1
}

################################################################################
# Databases and server parameters
################################################################################

variable "databases" {
  description = "Databases to create, keyed by name."
  type = map(object({
    charset   = optional(string, "UTF8")
    collation = optional(string, "en_US.utf8")
  }))
  default = {}
}

variable "extensions" {
  description = "Extensions to allow-list via azure.extensions (e.g. [\"PG_TRGM\", \"POSTGIS\"]). They still need CREATE EXTENSION per database."
  type        = list(string)
  default     = []
}

variable "server_parameters" {
  description = "Additional server parameters, keyed by parameter name."
  type        = map(string)
  default = {
    log_checkpoints    = "on"
    log_connections    = "on"
    log_disconnections = "on"
  }
}

################################################################################
# Encryption
################################################################################

variable "customer_managed_key" {
  description = <<-EOT
    Encrypt data, logs and backups with a Key Vault key (RSA 2048-4096, vault with purge protection).
    Only possible at creation time. With geo-redundant backups, `geo_backup` must reference a key in
    a vault located in the paired region; the module creates a separate identity there.
  EOT
  type = object({
    key_vault_id     = string
    key_vault_key_id = string
    geo_backup = optional(object({
      location         = string
      key_vault_id     = string
      key_vault_key_id = string
    }))
  })
  default = null
}

################################################################################
# Operations
################################################################################

variable "log_analytics_workspace" {
  description = "Send server logs and metrics to Log Analytics. Null disables diagnostics."
  type = object({
    id = string
  })
  default = null
}

variable "delete_lock_enabled" {
  description = "Add a CanNotDelete management lock to protect the server against accidental deletion."
  type        = bool
  default     = true
}
