terraform {
  required_version = ">= 1.11.1"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.0, < 6.0"
    }
  }
}

# Terraform signs in as a service-account client (client credentials grant) with the
# realm-management roles it needs, not as the admin user.
provider "keycloak" {
  url           = var.keycloak_url
  client_id     = var.keycloak_client_id
  client_secret = var.keycloak_client_secret
}

resource "keycloak_realm" "this" {
  realm                    = "platform"
  enabled                  = true
  ssl_required             = "all"
  registration_allowed     = false
  login_with_email_allowed = true
  duplicate_emails_allowed = false

  security_defenses {
    brute_force_detection {
      max_login_failures = 5
    }
  }
}

module "web_client" {
  source = "../../clients"

  realm_id            = keycloak_realm.this.id
  client_id           = "sample-web"
  name                = "Sample web app"
  access_type         = "CONFIDENTIAL"
  root_url            = "https://app.example.com"
  valid_redirect_uris = ["https://app.example.com/oauth2/callback"]
}

module "api_client" {
  source = "../../clients"

  realm_id    = keycloak_realm.this.id
  client_id   = "sample-api"
  access_type = "BEARER-ONLY"
}

module "roles" {
  source = "../../roles"

  realm_id = keycloak_realm.this.id

  realm_roles = {
    incident_responder = { name = "incident-responder", description = "Can acknowledge and resolve incidents" }
  }

  client_roles = {
    sample-web = {
      viewer = { name = "viewer" }
      editor = { name = "editor" }
      admin  = { name = "admin", composite_roles = ["viewer", "editor"] }
    }
  }

  depends_on = [module.web_client]
}

module "groups" {
  source = "../../groups"

  realm_id           = keycloak_realm.this.id
  default_attributes = { managed_by = "terraform" }
  exhaustive         = true

  groups = {
    platform = {
      name         = "platform"
      description  = "Platform team"
      client_roles = { sample-web = ["admin"] }
      subgroups = {
        oncall = {
          name        = "oncall"
          realm_roles = ["incident-responder"]
        }
      }
    }
    readers = {
      name         = "readers"
      client_roles = { sample-web = ["viewer"] }
    }
  }

  depends_on = [module.roles]
}

module "entra_id" {
  source = "../../identity-providers/microsoft"

  realm_id      = keycloak_realm.this.id
  tenant_id     = var.entra_tenant_id
  client_id     = var.entra_client_id
  client_secret = var.entra_client_secret

  attribute_mappers = {
    firstName = { json_field = "givenName" }
    lastName  = { json_field = "surname" }
  }
}

variable "keycloak_url" {
  description = "Base URL of the Keycloak server."
  type        = string
  default     = "https://keycloak.example.com"
}

variable "keycloak_client_id" {
  description = "Service-account client Terraform authenticates with."
  type        = string
  default     = "terraform"
}

variable "keycloak_client_secret" {
  description = "Secret of the Terraform service-account client (e.g. TF_VAR_keycloak_client_secret from a secret store)."
  type        = string
  sensitive   = true
}

variable "entra_tenant_id" {
  description = "Entra ID tenant whose users can sign in."
  type        = string
}

variable "entra_client_id" {
  description = "Application ID of the Entra ID app registration Keycloak brokers to."
  type        = string
}

variable "entra_client_secret" {
  description = "Client secret of that app registration."
  type        = string
  sensitive   = true
}

output "web_client_secret" {
  description = "Generated secret of the sample web client."
  value       = module.web_client.client_secret
  sensitive   = true
}

output "group_ids" {
  description = "Keycloak group IDs keyed by logical name."
  value       = module.groups.group_ids
}
