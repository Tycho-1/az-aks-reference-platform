variable "github_repository" {
  description = "GitHub repository in owner/name form, e.g. my-org/az-aks-reference-platform."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/name form."
  }
}

variable "environments" {
  description = <<-EOT
    GitHub environments the identities trust. Plan runs in `plan` (no approval needed); apply runs in
    `apply`, which should require reviewers and allow only the main branch.
  EOT
  type = object({
    plan  = optional(string, "production-plan")
    apply = optional(string, "production")
  })
  default = {}
}

variable "location" {
  description = "Region for the identities."
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Resource group created for the CI identities."
  type        = string
  default     = "rg-platform-ci-weu"
}

variable "state_storage_account_id" {
  description = "Resource ID of the Terraform state storage account (from modules/storage-backend)."
  type        = string
}

variable "state_container_name" {
  description = "State container the pipeline reads and writes."
  type        = string
  default     = "platform-prod"
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload   = "platform"
    managed_by = "terraform"
  }
}
