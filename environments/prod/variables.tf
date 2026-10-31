variable "workload" {
  description = "Short workload name used in resource names."
  type        = string
  default     = "platform"
}

variable "location" {
  description = "Primary Azure region."
  type        = string
  default     = "westeurope"
}

variable "location_short" {
  description = "Primary region abbreviation used in names."
  type        = string
  default     = "weu"
}

variable "paired_location" {
  description = "Paired region holding the geo-backup encryption key for PostgreSQL."
  type        = string
  default     = "northeurope"
}

variable "hub_address_space" {
  description = "Hub VNet address space."
  type        = string
  default     = "10.0.0.0/22"
}

variable "spoke_address_space" {
  description = "Spoke VNet address space. Must not overlap the hub or the AKS pod/service CIDRs."
  type        = string
  default     = "10.10.0.0/16"
}

variable "vpn_gateway_enabled" {
  description = <<-EOT
    Deploy a point-to-site VPN gateway in the hub so a laptop can join the VNet. False, the
    default, creates nothing. VpnGw1 bills for every hour it exists. The tunnel does not publish
    the hub private DNS zones; kubectl still needs a resolver or a hosts entry for
    privatelink.<region>.azmk8s.io. Prod does not need this for CI, Flux, or az aks command invoke.
  EOT
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "AKS minor version."
  type        = string
  default     = "1.37"
}

variable "node_availability_zones" {
  description = <<-EOT
    Availability zones for system and user node pools. Default spreads nodes across three zones for
    resilience in regions that support them (e.g. westeurope). Override in terraform.tfvars if a
    region or SKU supports fewer zones.
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "aks_admin_group_object_ids" {
  description = "Entra ID groups granted cluster-admin."
  type        = list(string)
}

variable "postgres_enabled" {
  description = <<-EOT
    Deploy private PostgreSQL Flexible Server (zone-redundant HA, geo-redundant backups, CMK).
    Set false for a cheaper smoke test of hub/spoke, firewall, and private AKS; re-enable before
    calling the environment production-ready.
  EOT
  type        = bool
  default     = true
}

variable "postgres_admin_group" {
  description = "Entra ID group that administers PostgreSQL. Required when postgres_enabled is true."
  type = object({
    object_id    = string
    display_name = string
  })
  default = null

  validation {
    condition     = !var.postgres_enabled || var.postgres_admin_group != null
    error_message = "postgres_admin_group is required when postgres_enabled is true."
  }
}

variable "operator_ip_ranges" {
  description = <<-EOT
    Public IPs of the Terraform runner, allowed on the Key Vault data plane so keys can be created.
    Leave empty when Terraform runs from a self-hosted runner with private endpoint access.
  EOT
  type        = list(string)
  default     = []
}

variable "acr_allowed_ip_ranges" {
  description = "Public IPs of hosted CI runners that push images. Leave empty to keep the registry private-only."
  type        = list(string)
  default     = []
}

variable "host_encryption_enabled" {
  description = "Encrypt node temp disks and caches at the host. Requires the EncryptionAtHost subscription feature."
  type        = bool
  default     = false
}

variable "system_node_pool_vm_size" {
  description = "VM size of the system node pool. Production default is Standard_D4ds_v5. A short test can use Standard_D2s_v3."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "system_node_pool_min_count" {
  description = "Minimum nodes in the system pool. Production default is 3. AKS does not allow Spot on this pool."
  type        = number
  default     = 3

  validation {
    condition     = var.system_node_pool_min_count >= 1
    error_message = "system_node_pool_min_count must be at least 1."
  }
}

variable "system_node_pool_os_disk_type" {
  description = "OS disk for the system pool. Use Managed for sizes without a temp disk large enough for Ephemeral (for example Standard_D2s_v3)."
  type        = string
  default     = "Ephemeral"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.system_node_pool_os_disk_type)
    error_message = "system_node_pool_os_disk_type must be Ephemeral or Managed."
  }
}

variable "apps_node_pool_vm_size" {
  description = "VM size of the apps user pool. Production default is Standard_D4ds_v5."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "apps_node_pool_min_count" {
  description = "Minimum nodes in the apps pool. Production default is 3."
  type        = number
  default     = 3

  validation {
    condition     = var.apps_node_pool_min_count >= 0
    error_message = "apps_node_pool_min_count must be at least 0."
  }
}

variable "apps_node_pool_max_count" {
  description = "Maximum nodes in the apps pool. Production default is 10."
  type        = number
  default     = 10
}

variable "apps_node_pool_os_disk_type" {
  description = "OS disk for the apps pool. Use Managed for sizes without a temp disk large enough for Ephemeral (for example Standard_D2s_v3)."
  type        = string
  default     = "Ephemeral"

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.apps_node_pool_os_disk_type)
    error_message = "apps_node_pool_os_disk_type must be Ephemeral or Managed."
  }
}

variable "apps_node_pool_priority" {
  description = <<-EOT
    Priority of the apps user node pool. Production default is Regular (on-demand).
    Set to Spot only for a short smoke test; Spot capacity can disappear and pods are evicted.
    The system pool stays Regular — AKS does not allow Spot on the system pool.
  EOT
  type        = string
  default     = "Regular"

  validation {
    condition     = contains(["Regular", "Spot"], var.apps_node_pool_priority)
    error_message = "apps_node_pool_priority must be Regular or Spot."
  }
}

check "apps_node_pool_scale" {
  assert {
    condition     = var.apps_node_pool_max_count >= var.apps_node_pool_min_count
    error_message = "apps_node_pool_max_count must be greater than or equal to apps_node_pool_min_count."
  }
}

variable "gitops_repository_url" {
  description = "HTTPS URL of the Git repository Flux reconciles (this repo's gitops/ folder). Null disables GitOps."
  type        = string
  default     = null
}

variable "alert_email_receivers" {
  description = "On-call email addresses for platform alerts, keyed by a static name."
  type        = map(string)
}

variable "monthly_budget" {
  description = "Monthly subscription budget in the billing currency. start_date is the first of a month (YYYY-MM-01T00:00:00Z)."
  type = object({
    amount     = number
    start_date = string
  })
  default = null
}

variable "owner" {
  description = "Owning team, applied as a tag."
  type        = string
  default     = "platform-team"
}
