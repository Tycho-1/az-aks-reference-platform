data "azuread_client_config" "current" {}

data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

resource "random_uuid" "app_role" {
  for_each = var.app_roles
}

resource "azuread_application" "this" {
  display_name            = var.display_name
  description             = var.description
  sign_in_audience        = var.sign_in_audience
  owners                  = coalesce(var.owners, [data.azuread_client_config.current.object_id])
  group_membership_claims = var.group_membership_claims
  prevent_duplicate_names = true

  api {
    requested_access_token_version = 2
  }

  web {
    redirect_uris = var.redirect_uris
    logout_url    = var.logout_url

    # Implicit flow is deprecated; confidential clients use the authorization code flow.
    implicit_grant {
      access_token_issuance_enabled = false
      id_token_issuance_enabled     = false
    }
  }

  dynamic "app_role" {
    for_each = var.app_roles
    content {
      id                   = random_uuid.app_role[app_role.key].result
      value                = app_role.key
      display_name         = app_role.value.display_name
      description          = app_role.value.description
      allowed_member_types = app_role.value.allowed_member_types
      enabled              = app_role.value.enabled
    }
  }

  optional_claims {
    dynamic "id_token" {
      for_each = var.optional_claims.id_token
      content {
        name                  = id_token.value.name
        essential             = id_token.value.essential
        additional_properties = id_token.value.additional_properties
      }
    }

    dynamic "access_token" {
      for_each = var.optional_claims.access_token
      content {
        name                  = access_token.value.name
        essential             = access_token.value.essential
        additional_properties = access_token.value.additional_properties
      }
    }
  }

  dynamic "required_resource_access" {
    for_each = length(var.graph_delegated_permissions) > 0 ? [1] : []
    content {
      resource_app_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]

      dynamic "resource_access" {
        for_each = toset(var.graph_delegated_permissions)
        content {
          id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids[resource_access.value]
          type = "Scope"
        }
      }
    }
  }
}

resource "azuread_service_principal" "this" {
  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = var.assignment_required
  owners                       = coalesce(var.owners, [data.azuread_client_config.current.object_id])
}

resource "azuread_app_role_assignment" "this" {
  for_each = var.app_role_assignments

  app_role_id         = random_uuid.app_role[each.value.app_role].result
  principal_object_id = each.value.principal_object_id
  resource_object_id  = azuread_service_principal.this.object_id

  depends_on = [azuread_application.this]
}

################################################################################
# Credentials
################################################################################

resource "time_rotating" "client_secret" {
  count = var.client_secret != null ? 1 : 0

  rotation_days = var.client_secret.rotation_days
}

resource "azuread_application_password" "this" {
  count = var.client_secret != null ? 1 : 0

  application_id = azuread_application.this.id
  display_name   = "terraform-managed-${formatdate("YYYY-MM-DD", time_rotating.client_secret[0].rfc3339)}"
  # Valid past the rotation date so a late pipeline run doesn't cause an outage.
  end_date = timeadd(time_rotating.client_secret[0].rotation_rfc3339, "${var.client_secret.grace_days * 24}h")

  rotate_when_changed = {
    rotation = time_rotating.client_secret[0].id
  }
}

resource "azuread_application_federated_identity_credential" "this" {
  for_each = var.federated_credentials

  application_id = azuread_application.this.id
  display_name   = each.key
  description    = each.value.description
  issuer         = each.value.issuer
  subject        = each.value.subject
  audiences      = each.value.audiences
}
