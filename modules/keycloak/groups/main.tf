locals {
  subgroups_flat = merge([
    for group_key, group in var.groups : {
      for subgroup_key, subgroup in group.subgroups : "${group_key}:${subgroup_key}" => merge(subgroup, {
        parent_key = group_key
      })
    }
  ]...)

  # Groups and subgroups share one keyspace for role lookups and assignments.
  all_groups = merge(var.groups, local.subgroups_flat)

  realm_role_names = toset(flatten([for group in values(local.all_groups) : group.realm_roles]))

  client_role_refs = merge(flatten([
    for group in values(local.all_groups) : [
      for client, roles in group.client_roles : {
        for role in roles : "${client}:${role}" => { client = client, role = role }
      }
    ]
  ])...)

  client_ids = toset([for ref in values(local.client_role_refs) : ref.client])

  role_ids = {
    for key, group in local.all_groups : key => concat(
      [for role in group.realm_roles : data.keycloak_role.realm[role].id],
      flatten([
        for client, roles in group.client_roles : [
          for role in roles : data.keycloak_role.client["${client}:${role}"].id
        ]
      ]),
    )
  }

  has_roles = {
    for key, group in local.all_groups : key => length(group.realm_roles) + length(flatten(values(group.client_roles))) > 0
  }
}

# Roles and clients are looked up by name at plan time. When they are created in the same
# configuration, add depends_on on the module so the lookups wait for them.
data "keycloak_role" "realm" {
  for_each = local.realm_role_names

  realm_id = var.realm_id
  name     = each.value
}

data "keycloak_openid_client" "this" {
  for_each = local.client_ids

  realm_id  = var.realm_id
  client_id = each.value
}

data "keycloak_role" "client" {
  for_each = local.client_role_refs

  realm_id  = var.realm_id
  client_id = data.keycloak_openid_client.this[each.value.client].id
  name      = each.value.role
}

resource "keycloak_group" "groups" {
  for_each = var.groups

  realm_id    = var.realm_id
  parent_id   = each.value.parent_id
  name        = each.value.name
  description = each.value.description
  attributes  = merge(var.default_attributes, each.value.attributes)
}

resource "keycloak_group" "subgroups" {
  for_each = local.subgroups_flat

  realm_id    = var.realm_id
  parent_id   = keycloak_group.groups[each.value.parent_key].id
  name        = each.value.name
  description = each.value.description
  attributes  = merge(var.default_attributes, each.value.attributes)
}

# One assignment per group: with exhaustive = true, two resources on the same group would
# remove each other's roles.
resource "keycloak_group_roles" "group_roles" {
  for_each = { for key in keys(var.groups) : key => key if local.has_roles[key] }

  realm_id   = var.realm_id
  group_id   = keycloak_group.groups[each.key].id
  role_ids   = local.role_ids[each.key]
  exhaustive = var.exhaustive
}

resource "keycloak_group_roles" "subgroup_roles" {
  for_each = { for key in keys(local.subgroups_flat) : key => key if local.has_roles[key] }

  realm_id   = var.realm_id
  group_id   = keycloak_group.subgroups[each.key].id
  role_ids   = local.role_ids[each.key]
  exhaustive = var.exhaustive
}

moved {
  from = keycloak_group_roles.group_realm_roles
  to   = keycloak_group_roles.group_roles
}

moved {
  from = keycloak_group_roles.subgroup_realm_roles
  to   = keycloak_group_roles.subgroup_roles
}
