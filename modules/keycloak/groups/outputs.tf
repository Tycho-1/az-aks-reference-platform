output "groups" {
  description = "Groups keyed by logical name, with `id`, `name`, `path` and their `subgroups` (same shape, keyed by subgroup name)."
  value = {
    for key, group in keycloak_group.groups : key => {
      id   = group.id
      name = group.name
      path = group.path
      subgroups = {
        for subgroup_key in keys(var.groups[key].subgroups) : subgroup_key => {
          id   = keycloak_group.subgroups["${key}:${subgroup_key}"].id
          name = keycloak_group.subgroups["${key}:${subgroup_key}"].name
          path = keycloak_group.subgroups["${key}:${subgroup_key}"].path
        }
      }
    }
  }
}

output "group_ids" {
  description = "Group IDs keyed by logical name; subgroups use `<group>:<subgroup>`. Useful for identity provider group mappers."
  value = merge(
    { for key, group in keycloak_group.groups : key => group.id },
    { for key, group in keycloak_group.subgroups : key => group.id },
  )
}
