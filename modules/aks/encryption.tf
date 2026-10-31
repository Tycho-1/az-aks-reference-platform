################################################################################
# Node disk encryption (disk encryption set)
################################################################################

resource "azurerm_user_assigned_identity" "disk_encryption" {
  count = var.disk_encryption != null ? 1 : 0

  name                = "id-${var.name}-disk-encryption"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "disk_encryption_key" {
  count = var.disk_encryption != null ? 1 : 0

  scope                            = var.disk_encryption.key_vault_id
  role_definition_name             = "Key Vault Crypto Service Encryption User"
  principal_id                     = azurerm_user_assigned_identity.disk_encryption[0].principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "time_sleep" "disk_encryption_rbac" {
  count = var.disk_encryption != null ? 1 : 0

  create_duration = "60s"

  triggers = {
    role_assignment = azurerm_role_assignment.disk_encryption_key[0].id
  }
}

resource "azurerm_disk_encryption_set" "this" {
  count = var.disk_encryption != null ? 1 : 0

  name                      = "des-${var.name}"
  location                  = var.location
  resource_group_name       = var.resource_group_name
  key_vault_key_id          = var.disk_encryption.key_vault_key_id
  auto_key_rotation_enabled = true
  tags                      = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.disk_encryption[0].id]
  }

  depends_on = [time_sleep.disk_encryption_rbac]
}

resource "azurerm_role_assignment" "control_plane_disk_encryption_set" {
  count = var.disk_encryption != null ? 1 : 0

  scope                            = azurerm_disk_encryption_set.this[0].id
  role_definition_name             = "Reader"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

################################################################################
# etcd secret encryption (KMS)
################################################################################

resource "azurerm_role_assignment" "control_plane_kms_crypto" {
  count = var.kms != null ? 1 : 0

  scope                            = var.kms.key_vault_id
  role_definition_name             = "Key Vault Crypto User"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "control_plane_kms_private_link" {
  # AKS creates its own private link to a private vault, which needs Key Vault Contributor.
  count = var.kms == null ? 0 : (var.kms.network_access == "Private" ? 1 : 0)

  scope                            = var.kms.key_vault_id
  role_definition_name             = "Key Vault Contributor"
  principal_id                     = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}
