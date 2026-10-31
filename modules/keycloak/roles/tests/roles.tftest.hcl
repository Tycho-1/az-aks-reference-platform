mock_provider "keycloak" {}

variables {
  realm_id = "platform"
}

run "realm_roles_with_composite" {
  command = plan

  variables {
    realm_roles = {
      reader = { name = "reader" }
      writer = { name = "writer" }
      admin  = { name = "admin", composite_roles = ["reader", "writer"] }
    }
  }

  assert {
    condition     = toset(keys(keycloak_role.realm_roles)) == toset(["reader", "writer"])
    error_message = "Non-composite roles belong to the base tier."
  }

  assert {
    condition     = keys(keycloak_role.realm_role_composites) == ["admin"]
    error_message = "Composite roles must be created once, in the composite tier."
  }

  assert {
    condition     = keycloak_role.realm_role_composites["admin"].name == "admin"
    error_message = "The composite tier should create the admin role."
  }
}

run "client_roles" {
  command = plan

  variables {
    client_roles = {
      sample-web = {
        viewer = { name = "viewer" }
        editor = { name = "editor", composite_roles = ["viewer"] }
      }
    }
  }

  assert {
    condition     = keys(keycloak_role.client_roles) == ["sample-web:viewer"]
    error_message = "Unexpected base client roles."
  }

  assert {
    condition     = keys(keycloak_role.client_role_composites) == ["sample-web:editor"]
    error_message = "Unexpected composite client roles."
  }

  assert {
    condition     = keycloak_role.client_roles["sample-web:viewer"].client_id == data.keycloak_openid_client.this["sample-web"].id
    error_message = "Client roles must be created on the looked-up client."
  }
}

run "rejects_unknown_composite" {
  command = plan

  variables {
    realm_roles = {
      admin = { name = "admin", composite_roles = ["missing"] }
    }
  }

  expect_failures = [var.realm_roles]
}

run "rejects_nested_composite" {
  command = plan

  variables {
    realm_roles = {
      reader = { name = "reader" }
      editor = { name = "editor", composite_roles = ["reader"] }
      admin  = { name = "admin", composite_roles = ["editor"] }
    }
  }

  expect_failures = [var.realm_roles]
}

run "rejects_cross_client_composite" {
  command = plan

  variables {
    client_roles = {
      app-a = { viewer = { name = "viewer" } }
      app-b = { editor = { name = "editor", composite_roles = ["viewer"] } }
    }
  }

  expect_failures = [var.client_roles]
}

run "rejects_empty_realm" {
  command = plan

  variables {
    realm_id = ""
  }

  expect_failures = [var.realm_id]
}
