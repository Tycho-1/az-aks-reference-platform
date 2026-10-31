plugin "azurerm" {
  enabled = true
  version = "0.30.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

config {
  # Lint module calls with their real inputs so cross-module issues surface in the examples.
  call_module_type = "local"
}

# Deletion protection is a CanNotDelete management lock, which a caller can remove per
# environment, plus Key Vault purge protection. prevent_destroy has to be a literal, so it
# would make tearing down non-production environments impossible.
rule "azurerm_resources_missing_prevent_destroy" {
  enabled = false
}

# Module READMEs are hand-written; terraform-docs owns the generated reference sections.
rule "terraform_documented_variables" {
  enabled = false
}

rule "terraform_documented_outputs" {
  enabled = false
}
