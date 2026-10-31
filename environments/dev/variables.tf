variable "workload" {
  description = "Short workload name used in resource names."
  type        = string
  default     = "platform"
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "environment must be dev, test or prod."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "location_short" {
  description = "Region abbreviation used in names."
  type        = string
  default     = "weu"
}

variable "address_space" {
  description = "VNet address space. Must not overlap the AKS pod and service CIDRs."
  type        = string
  default     = "10.10.0.0/16"
}

variable "kubernetes_version" {
  description = "AKS minor version."
  type        = string
  default     = "1.37"
}

variable "node_availability_zones" {
  description = <<-EOT
    Availability zones for system and user node pools. Production-shaped default is [1, 2, 3] when the
    region and SKU support them (typical for westeurope, germanywestcentral). Override in
    terraform.tfvars per region. northeurope with Standard_D2s_v3 was verified on ["2"] only.
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "aks_admin_group_object_ids" {
  description = "Entra ID groups granted cluster-admin."
  type        = list(string)
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach the public API server (your office/VPN and CI egress)."
  type        = list(string)
  default     = []
}

variable "postgres_enabled" {
  description = "Deploy a private PostgreSQL Flexible Server (burstable SKU when environment is dev)."
  type        = bool
  default     = false
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

# Cross-variable check: the prod profile in this root always includes the data tier.
check "postgres_required_for_prod_profile" {
  assert {
    condition     = var.environment != "prod" || var.postgres_enabled
    error_message = "postgres_enabled must be true when environment is prod."
  }
}

variable "owner" {
  description = "Owning team, applied as a tag."
  type        = string
  default     = "platform-team"
}
