################################################################################
# General
################################################################################

variable "name" {
  description = "Name of the AKS cluster (e.g. aks-platform-prod-weu)."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,61}[a-zA-Z0-9]$", var.name))
    error_message = "Cluster name must be 2-63 characters of letters, digits, '-' or '_' and start/end alphanumeric."
  }
}

variable "resource_group_name" {
  description = "Name of an existing resource group for the cluster resource."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the API server FQDN. Defaults to the cluster name."
  type        = string
  default     = null
}

variable "node_resource_group_name" {
  description = "Name of the AKS-managed node resource group. Defaults to MC_<rg>_<cluster>_<region>."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

################################################################################
# Versioning, SLA and upgrades
################################################################################

variable "kubernetes_version" {
  description = <<-EOT
    Kubernetes minor version, e.g. "1.33". Pin the minor only: patch versions are applied by
    `automatic_upgrade_channel = "patch"` without causing Terraform drift. Null uses the AKS default.
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.kubernetes_version == null || can(regex("^1\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a minor version such as \"1.33\" (no patch component)."
  }
}

variable "sku_tier" {
  description = "Control plane tier. Standard provides the financially backed uptime SLA and is recommended for production."
  type        = string
  default     = "Standard"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku_tier)
    error_message = "sku_tier must be Free, Standard or Premium."
  }
}

variable "automatic_upgrade_channel" {
  description = "Cluster auto-upgrade channel. 'patch' keeps the pinned minor version patched."
  type        = string
  default     = "patch"

  validation {
    condition     = var.automatic_upgrade_channel == null || contains(["patch", "rapid", "node-image", "stable"], var.automatic_upgrade_channel)
    error_message = "automatic_upgrade_channel must be patch, rapid, node-image, stable or null."
  }
}

variable "node_os_upgrade_channel" {
  description = "Node OS security patching channel."
  type        = string
  default     = "NodeImage"

  validation {
    condition     = contains(["None", "Unmanaged", "SecurityPatch", "NodeImage"], var.node_os_upgrade_channel)
    error_message = "node_os_upgrade_channel must be None, Unmanaged, SecurityPatch or NodeImage."
  }
}

variable "maintenance_window_auto_upgrade" {
  description = "Planned maintenance window for cluster upgrades. Times are in `utc_offset`."
  type = object({
    frequency   = optional(string, "Weekly")
    interval    = optional(number, 1)
    duration    = optional(number, 4)
    day_of_week = optional(string, "Sunday")
    start_time  = optional(string, "02:00")
    utc_offset  = optional(string, "+00:00")
  })
  default = {}
}

variable "maintenance_window_node_os" {
  description = "Planned maintenance window for node OS image updates."
  type = object({
    frequency   = optional(string, "Weekly")
    interval    = optional(number, 1)
    duration    = optional(number, 4)
    day_of_week = optional(string, "Saturday")
    start_time  = optional(string, "02:00")
    utc_offset  = optional(string, "+00:00")
  })
  default = {}
}

################################################################################
# Networking
################################################################################

variable "node_subnet_id" {
  description = "Subnet ID for the system node pool (and user pools that don't set their own subnet)."
  type        = string
}

variable "network_profile" {
  description = <<-EOT
    Cluster networking. The module always uses Azure CNI Overlay with the Cilium data plane,
    which is Microsoft's recommended default for new clusters (eBPF data plane, network policy,
    no pod IP exhaustion in the VNet).
  EOT
  type = object({
    pod_cidr       = optional(string, "10.244.0.0/16")
    service_cidr   = optional(string, "10.245.0.0/16")
    dns_service_ip = optional(string, "10.245.0.10")
    outbound_type  = optional(string, "loadBalancer")
  })
  default = {}

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.network_profile.outbound_type)
    error_message = "outbound_type must be loadBalancer, userDefinedRouting, managedNATGateway or userAssignedNATGateway."
  }

  validation {
    condition     = can(cidrhost(var.network_profile.pod_cidr, 0)) && can(cidrhost(var.network_profile.service_cidr, 0))
    error_message = "pod_cidr and service_cidr must be valid CIDR blocks."
  }
}

variable "private_cluster" {
  description = <<-EOT
    Private API server. `private_dns_zone_id` may be "System", "None" or the ID of a
    privatelink.<region>.azmk8s.io zone (required for hub-and-spoke with central DNS).
  EOT
  type = object({
    enabled             = optional(bool, false)
    private_dns_zone_id = optional(string, "System")
    public_fqdn_enabled = optional(bool, false)
  })
  default = {}
}

variable "api_server_authorized_ip_ranges" {
  description = "CIDRs allowed to reach a public API server. Strongly recommended when the cluster is not private."
  type        = list(string)
  default     = []
}

variable "api_server_vnet_integration" {
  description = "API server VNet integration: projects the API server into a delegated subnet. Null disables it."
  type = object({
    subnet_id = string
  })
  default = null
}

################################################################################
# Identity and access
################################################################################

variable "admin_group_object_ids" {
  description = "Entra ID group object IDs granted cluster-admin. Required because local accounts are disabled by default."
  type        = list(string)
  default     = []
}

variable "local_account_disabled" {
  description = "Disable the static local admin kubeconfig so all access goes through Entra ID."
  type        = bool
  default     = true
}

variable "acr_ids" {
  description = "Container registry IDs the kubelet identity gets AcrPull on, keyed by a static name."
  type        = map(string)
  default     = {}
}

variable "control_plane_role_assignments" {
  description = <<-EOT
    Extra roles for the control plane identity, granted before the cluster is created and keyed by a
    static name. Typical entries: Network Contributor on a route table in another resource group
    (outbound_type = userDefinedRouting) and Private DNS Zone Contributor on a central
    privatelink.<region>.azmk8s.io zone (private cluster).
  EOT
  type = map(object({
    scope                = string
    role_definition_name = string
  }))
  default = {}
}

################################################################################
# Encryption with customer-managed keys
################################################################################

variable "disk_encryption" {
  description = <<-EOT
    Encrypt node OS and data disks with a customer-managed key through a disk encryption set.
    Only possible at cluster creation. Use a versionless key ID so rotation is picked up automatically.
  EOT
  type = object({
    key_vault_id     = string
    key_vault_key_id = string
  })
  default = null
}

variable "kms" {
  description = <<-EOT
    Encrypt Kubernetes secrets in etcd with a Key Vault key (KMS). `key_vault_key_id` must be the
    versioned key ID. `network_access = "Private"` requires api_server_vnet_integration and a
    private endpoint for the vault in the cluster VNet.
  EOT
  type = object({
    key_vault_id     = string
    key_vault_key_id = string
    network_access   = optional(string, "Private")
  })
  default = null

  validation {
    condition     = var.kms == null || contains(["Public", "Private"], try(var.kms.network_access, ""))
    error_message = "kms.network_access must be Public or Private."
  }
}

################################################################################
# Node pools
################################################################################

variable "system_node_pool" {
  description = <<-EOT
    System node pool. It is tainted with CriticalAddonsOnly so application workloads land on
    user pools. Microsoft recommends at least three nodes across availability zones.
  EOT
  type = object({
    name                        = optional(string, "system")
    vm_size                     = optional(string, "Standard_D4ds_v5")
    zones                       = optional(list(string), ["1", "2", "3"])
    min_count                   = optional(number, 3)
    max_count                   = optional(number, 5)
    max_pods                    = optional(number, 110)
    os_sku                      = optional(string, "AzureLinux")
    os_disk_type                = optional(string, "Ephemeral")
    os_disk_size_gb             = optional(number)
    host_encryption_enabled     = optional(bool, false)
    max_surge                   = optional(string, "33%")
    drain_timeout_in_minutes    = optional(number, 30)
    temporary_name_for_rotation = optional(string, "systemtmp")
  })
  default = {}

  validation {
    condition     = var.system_node_pool.min_count >= 1 && var.system_node_pool.max_count >= var.system_node_pool.min_count
    error_message = "system_node_pool requires min_count >= 1 and max_count >= min_count."
  }
}

variable "node_pools" {
  description = "Additional user node pools keyed by pool name (max 12 lowercase alphanumeric characters)."
  type = map(object({
    vm_size                  = string
    zones                    = optional(list(string), ["1", "2", "3"])
    auto_scaling_enabled     = optional(bool, true)
    node_count               = optional(number)
    min_count                = optional(number, 1)
    max_count                = optional(number, 5)
    max_pods                 = optional(number, 110)
    os_sku                   = optional(string, "AzureLinux")
    os_disk_type             = optional(string, "Ephemeral")
    os_disk_size_gb          = optional(number)
    host_encryption_enabled  = optional(bool, false)
    vnet_subnet_id           = optional(string)
    priority                 = optional(string, "Spot")
    spot_max_price           = optional(number, -1)
    node_labels              = optional(map(string), {})
    node_taints              = optional(list(string), [])
    max_surge                = optional(string, "33%")
    drain_timeout_in_minutes = optional(number, 30)
    tags                     = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "Node pool names must start with a letter and be at most 12 lowercase alphanumeric characters."
  }

  validation {
    condition = alltrue([
      for p in values(var.node_pools) :
      p.auto_scaling_enabled ? (p.min_count >= 0 && p.max_count >= p.min_count) : p.node_count != null
    ])
    error_message = "Autoscaled pools need max_count >= min_count >= 0; fixed-size pools need node_count."
  }

  validation {
    condition     = alltrue([for p in values(var.node_pools) : contains(["Regular", "Spot"], p.priority)])
    error_message = "priority must be Regular or Spot."
  }
}

################################################################################
# Add-ons and features
################################################################################

variable "azure_policy_enabled" {
  description = "Enable the Azure Policy add-on (Gatekeeper) to enforce the AKS policy initiatives."
  type        = bool
  default     = true
}

variable "key_vault_secrets_provider" {
  description = "Secrets Store CSI driver for Key Vault. Pair with workload identity instead of Kubernetes secrets."
  type = object({
    enabled                  = optional(bool, true)
    secret_rotation_interval = optional(string, "2m")
  })
  default = {}
}

variable "image_cleaner_interval_hours" {
  description = "Interval for Image Cleaner (removes unused, vulnerable images from nodes). Null disables it."
  type        = number
  default     = 168
}

variable "workload_autoscaler" {
  description = "Managed KEDA and Vertical Pod Autoscaler add-ons."
  type = object({
    keda_enabled                    = optional(bool, false)
    vertical_pod_autoscaler_enabled = optional(bool, false)
  })
  default = {}
}

variable "web_app_routing" {
  description = <<-EOT
    Managed application routing add-on (Microsoft-managed ingress). Null disables it. Pass Azure DNS
    zone IDs to let it manage records.
  EOT
  type = object({
    dns_zone_ids = optional(list(string), [])
  })
  default = null
}

variable "cost_analysis_enabled" {
  description = "Enable AKS cost analysis (requires Standard or Premium tier)."
  type        = bool
  default     = true
}

################################################################################
# Observability and security monitoring
################################################################################

variable "log_analytics" {
  description = <<-EOT
    Log Analytics integration: Container Insights, control plane diagnostic logs and (optionally)
    the Defender for Containers sensor. `kube-audit-admin` is the cost-effective audit category;
    add `kube-audit` only if you need read events too. Null disables all of it.
  EOT
  type = object({
    workspace_id               = string
    container_insights_enabled = optional(bool, true)
    defender_enabled           = optional(bool, false)
    diagnostic_log_categories  = optional(list(string), ["kube-audit-admin", "guard", "kube-controller-manager", "cluster-autoscaler"])
  })
  default = null
}

variable "managed_prometheus" {
  description = "Azure Monitor managed Prometheus. Null disables it."
  type = object({
    monitor_workspace_id = string
  })
  default = null
}

################################################################################
# GitOps
################################################################################

variable "gitops" {
  description = <<-EOT
    Optional Flux v2 (AKS GitOps extension) bootstrap. In-cluster platform components
    (cert-manager, ingress, policies, etc.) should be delivered from Git instead of Terraform.
    The repository must be public or reachable with `https_user` + a PAT supplied separately.
  EOT
  type = object({
    repository_url = string
    branch         = optional(string, "main")
    kustomizations = map(object({
      path       = string
      depends_on = optional(list(string), [])
      prune      = optional(bool, true)
    }))
  })
  default = null
}
