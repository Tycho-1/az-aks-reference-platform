# Plans the prod environment against mocked providers.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id       = "00000000-0000-0000-0000-000000000001"
      object_id       = "00000000-0000-0000-0000-000000000002"
      subscription_id = "00000000-0000-0000-0000-000000000003"
    }
  }
}

mock_provider "random" {}

variables {
  aks_admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]
  postgres_admin_group = {
    object_id    = "22222222-2222-2222-2222-222222222222"
    display_name = "sg-platform-postgres-admins"
  }
  operator_ip_ranges    = ["203.0.113.10"]
  gitops_repository_url = "https://github.com/example-org/az-aks-reference-platform"
  alert_email_receivers = { oncall = "oncall@example.com" }
  monthly_budget = {
    amount     = 3000
    start_date = "2026-10-01T00:00:00Z"
  }
}

run "prod_plan" {
  command = plan

  # Pin the production defaults so a local smoke-test terraform.tfvars cannot change this run.
  variables {
    location         = "westeurope"
    location_short   = "weu"
    postgres_enabled = true
    postgres_admin_group = {
      object_id    = "22222222-2222-2222-2222-222222222222"
      display_name = "sg-platform-postgres-admins"
    }
    apps_node_pool_priority  = "Regular"
    apps_node_pool_vm_size   = "Standard_D4ds_v5"
    system_node_pool_vm_size = "Standard_D4ds_v5"
    gitops_repository_url    = "https://github.com/example-org/az-aks-reference-platform"
    vpn_gateway_enabled      = false
  }

  assert {
    condition     = module.aks.name == "aks-platform-prod-weu"
    error_message = "Unexpected cluster name."
  }

  assert {
    condition     = length(module.alerting.metric_alert_ids) == 14
    error_message = "Expected metric alerts for AKS, PostgreSQL, the firewall and both Key Vaults."
  }

  assert {
    condition     = contains(local.gitops_egress_fqdns, "github.com")
    error_message = "The firewall must allow the GitOps repository host."
  }

  assert {
    condition     = azurerm_federated_identity_credential.sample_api.subject == "system:serviceaccount:sample-api:sample-api"
    error_message = "The sample API identity must trust only its Kubernetes service account."
  }

  assert {
    condition     = module.hub.bastion_host_name == "bas-hub-prod-weu"
    error_message = "Prod should deploy hub Bastion for operator access."
  }

  assert {
    condition     = module.hub.vpn_gateway_name == null
    error_message = "The VPN gateway must stay off unless vpn_gateway_enabled is true."
  }

  assert {
    condition     = module.aks.web_app_routing_enabled
    error_message = "Managed application routing must be enabled for the sample API ingress policy."
  }

  assert {
    condition     = module.aks.node_pool_priorities["apps"] == "Regular"
    error_message = "Prod apps pool defaults to Regular (on-demand)."
  }
}

run "prod_plan_spot_apps" {
  command = plan

  variables {
    apps_node_pool_priority       = "Spot"
    apps_node_pool_vm_size        = "Standard_D2s_v3"
    apps_node_pool_min_count      = 1
    apps_node_pool_os_disk_type   = "Managed"
    system_node_pool_vm_size      = "Standard_D2s_v3"
    system_node_pool_min_count    = 1
    system_node_pool_os_disk_type = "Managed"
  }

  assert {
    condition     = module.aks.node_pool_priorities["apps"] == "Spot"
    error_message = "Smoke tests should be able to set the apps pool to Spot via tfvars."
  }

  assert {
    condition     = module.aks.node_pool_vm_sizes["apps"] == "Standard_D2s_v3" && module.aks.system_node_pool_vm_size == "Standard_D2s_v3"
    error_message = "Smoke tests should be able to set both pool VM sizes via tfvars."
  }
}

run "prod_plan_without_postgres" {
  command = plan

  variables {
    postgres_enabled      = false
    postgres_admin_group  = null
    gitops_repository_url = null
    monthly_budget        = null
  }

  assert {
    condition     = length(module.postgres) == 0
    error_message = "postgres_enabled = false should not create PostgreSQL."
  }

  assert {
    condition     = length(module.alerting.metric_alert_ids) == 8
    error_message = "Without PostgreSQL, metric alerts should cover AKS, firewall and primary Key Vault only."
  }

  assert {
    condition     = length(local.gitops_egress_fqdns) == 0
    error_message = "GitOps disabled should not add firewall FQDN rules for the repository host."
  }
}

run "prod_plan_with_vpn" {
  command = plan

  variables {
    location            = "westeurope"
    location_short      = "weu"
    vpn_gateway_enabled = true
  }

  assert {
    condition     = module.hub.vpn_gateway_name == "vpng-hub-prod-weu"
    error_message = "vpn_gateway_enabled = true should create the hub point-to-site gateway."
  }
}
