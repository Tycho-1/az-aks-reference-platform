mock_provider "keycloak" {}

variables {
  realm_id = "platform"
  groups = {
    platform = {
      name         = "platform"
      description  = "Platform team"
      attributes   = { cost_center = "1234" }
      realm_roles  = ["offline_access"]
      client_roles = { sample-web = ["viewer", "editor"] }
      subgroups = {
        oncall = {
          name        = "oncall"
          realm_roles = ["incident-responder"]
        }
        readers = {
          name = "readers"
        }
      }
    }
    auditors = {
      name = "auditors"
    }
  }
  default_attributes = { managed_by = "terraform", cost_center = "0000" }
}

run "groups_and_subgroups" {
  command = plan

  assert {
    condition     = keys(keycloak_group.subgroups) == ["platform:oncall", "platform:readers"]
    error_message = "Subgroups should be keyed by parent and subgroup name."
  }

  assert {
    condition     = keycloak_group.groups["platform"].description == "Platform team"
    error_message = "description must be passed to the group."
  }

  assert {
    condition     = keycloak_group.groups["platform"].attributes == tomap({ managed_by = "terraform", cost_center = "1234" })
    error_message = "Group attributes must override default_attributes."
  }
}

run "one_role_assignment_per_group" {
  command = plan

  assert {
    condition     = keys(keycloak_group_roles.group_roles) == ["platform"]
    error_message = "Only groups with roles get an assignment."
  }

  assert {
    condition     = length(keycloak_group_roles.group_roles["platform"].role_ids) == 3
    error_message = "Realm and client roles must be assigned through the same resource."
  }

  assert {
    condition     = keys(keycloak_group_roles.subgroup_roles) == ["platform:oncall"]
    error_message = "Subgroup roles must be assigned, including realm roles the parent doesn't have."
  }

  assert {
    condition     = !keycloak_group_roles.group_roles["platform"].exhaustive
    error_message = "Role assignment must be additive by default."
  }
}

run "role_lookups_include_subgroups" {
  command = plan

  assert {
    condition     = toset(keys(data.keycloak_role.realm)) == toset(["offline_access", "incident-responder"])
    error_message = "Realm roles of subgroups must be looked up too."
  }

  assert {
    condition     = toset(keys(data.keycloak_role.client)) == toset(["sample-web:viewer", "sample-web:editor"])
    error_message = "Unexpected client role lookups."
  }
}

run "rejects_empty_subgroup_name" {
  command = plan

  variables {
    groups = {
      platform = {
        name      = "platform"
        subgroups = { oncall = { name = "" } }
      }
    }
  }

  expect_failures = [var.groups]
}
