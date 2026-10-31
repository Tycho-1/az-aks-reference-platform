output "realm_roles" {
  description = "Realm roles keyed by logical name, with `id` and `name`."
  value = {
    for key, role in merge(keycloak_role.realm_roles, keycloak_role.realm_role_composites) : key => {
      id   = role.id
      name = role.name
    }
  }
}

output "client_roles" {
  description = "Client roles keyed by client ID, then by logical role name, with `id` and `name`."
  value = {
    for client_id, roles in var.client_roles : client_id => {
      for key in keys(roles) : key => {
        id   = merge(keycloak_role.client_roles, keycloak_role.client_role_composites)["${client_id}:${key}"].id
        name = roles[key].name
      }
    }
  }
}
