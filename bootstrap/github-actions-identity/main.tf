################################################################################
# GitHub Actions identities (OIDC, no secrets)
#
# Two user-assigned managed identities with federated credentials:
#   plan  - read-only on the subscription, can lock and read state
#   apply - can change resources and assign non-privileged roles
################################################################################

data "azurerm_subscription" "current" {}

locals {
  github_issuer = "https://token.actions.githubusercontent.com"
  state_scope   = "${var.state_storage_account_id}/blobServices/default/containers/${var.state_container_name}"

  # Owner, User Access Administrator, Role Based Access Control Administrator.
  privileged_role_ids = "8e3af657-a8ff-443c-a75c-2fe8c4bcb635, 18d7d88d-d35e-4fb5-a5c3-7773c20a72d9, f58310d9-a9f6-439a-9e8d-f62e7b41a168"

  identities = {
    plan = {
      environment = var.environments.plan
      roles = {
        reader           = { scope = data.azurerm_subscription.current.id, role = "Reader" }
        key-vault-reader = { scope = data.azurerm_subscription.current.id, role = "Key Vault Reader" }
        state            = { scope = local.state_scope, role = "Storage Blob Data Contributor" }
      }
    }
    apply = {
      environment = var.environments.apply
      roles = {
        contributor = { scope = data.azurerm_subscription.current.id, role = "Contributor" }
        state       = { scope = local.state_scope, role = "Storage Blob Data Contributor" }
      }
    }
  }

  role_assignments = merge([
    for identity, cfg in local.identities : {
      for name, ra in cfg.roles : "${identity}-${name}" => merge(ra, { identity = identity })
    }
  ]...)
}

resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_user_assigned_identity" "this" {
  for_each = local.identities

  name                = "id-github-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "this" {
  for_each = local.identities

  name                      = "github-${each.value.environment}"
  user_assigned_identity_id = azurerm_user_assigned_identity.this[each.key].id
  issuer                    = local.github_issuer
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = "repo:${var.github_repository}:environment:${each.value.environment}"
}

resource "azurerm_role_assignment" "this" {
  for_each = local.role_assignments

  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.this[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
}

# The platform creates role assignments (AcrPull, Key Vault roles, Network Contributor), so apply
# needs RBAC write. The condition blocks granting or removing the privileged admin roles, so a
# compromised pipeline can't escalate to Owner.
resource "azurerm_role_assignment" "apply_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.this["apply"].principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAllValues:GuidNotEquals {${local.privileged_role_ids}}
     )
    )
  EOT
}
