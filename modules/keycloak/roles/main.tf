locals {
  client_roles_flat = merge([
    for client_id, roles in var.client_roles : {
      for role_key, role in roles : "${client_id}:${role_key}" => {
        client_id = client_id
        role_key  = role_key
        role      = role
      }
    }
  ]...)
}

# Looked up by client_id at plan time. When the clients are created in the same configuration,
# add depends_on on the module so the lookup waits for them.
data "keycloak_openid_client" "this" {
  for_each = toset(keys(var.client_roles))

  realm_id  = var.realm_id
  client_id = each.value
}

################################################################################
# Roles are created in two tiers: a composite references the IDs of its member roles, and a
# resource cannot reference instances of itself.
################################################################################

resource "keycloak_role" "realm_roles" {
  for_each = { for key, role in var.realm_roles : key => role if length(role.composite_roles) == 0 }

  realm_id    = var.realm_id
  name        = each.value.name
  description = each.value.description
  attributes  = each.value.attributes
}

resource "keycloak_role" "realm_role_composites" {
  for_each = { for key, role in var.realm_roles : key => role if length(role.composite_roles) > 0 }

  realm_id        = var.realm_id
  name            = each.value.name
  description     = each.value.description
  attributes      = each.value.attributes
  composite_roles = [for key in each.value.composite_roles : keycloak_role.realm_roles[key].id]
}

resource "keycloak_role" "client_roles" {
  for_each = { for key, item in local.client_roles_flat : key => item if length(item.role.composite_roles) == 0 }

  realm_id    = var.realm_id
  client_id   = data.keycloak_openid_client.this[each.value.client_id].id
  name        = each.value.role.name
  description = each.value.role.description
  attributes  = each.value.role.attributes
}

resource "keycloak_role" "client_role_composites" {
  for_each = { for key, item in local.client_roles_flat : key => item if length(item.role.composite_roles) > 0 }

  realm_id    = var.realm_id
  client_id   = data.keycloak_openid_client.this[each.value.client_id].id
  name        = each.value.role.name
  description = each.value.role.description
  attributes  = each.value.role.attributes
  composite_roles = [
    for key in each.value.role.composite_roles : keycloak_role.client_roles["${each.value.client_id}:${key}"].id
  ]
}
