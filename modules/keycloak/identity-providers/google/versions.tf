terraform {
  required_version = ">= 1.11.1"

  required_providers {
    keycloak = {
      source  = "keycloak/keycloak"
      version = ">= 5.0, < 6.0"
    }
  }
}
