mock_provider "azurerm" {}

variables {
  name                = "vnet-hub-test-weu"
  resource_group_name = "rg-hub"
  location            = "westeurope"
  address_space       = ["10.0.0.0/22"]

  firewall = {
    name                  = "afw-hub-test-weu"
    subnet_address_prefix = "10.0.0.0/26"
  }
}

run "firewall_defaults" {
  command = plan

  assert {
    condition     = azurerm_firewall_policy.this.dns[0].proxy_enabled
    error_message = "DNS proxy must be enabled so spokes can use the firewall for DNS."
  }

  assert {
    condition     = azurerm_firewall_policy.this.threat_intelligence_mode == "Deny"
    error_message = "Threat intelligence should deny by default."
  }

  assert {
    condition     = length(azurerm_firewall.this.zones) == 3
    error_message = "The firewall should be zone redundant."
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.aks) == 0 && length(azurerm_firewall_policy_rule_collection_group.platform) == 0
    error_message = "No allow rules should exist unless requested."
  }

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 3
    error_message = "The default central private DNS zones should be created."
  }

  assert {
    condition     = length(azurerm_virtual_network_gateway.vpn) == 0 && length(azurerm_subnet.gateway) == 0
    error_message = "The VPN gateway must stay off unless vpn_gateway is set."
  }
}

run "aks_egress_rules" {
  command = plan

  variables {
    aks_egress = {
      source_addresses = ["10.10.0.0/22"]
      additional_fqdns = ["github.com"]
    }
  }

  assert {
    condition     = one(azurerm_firewall_policy_rule_collection_group.aks[0].application_rule_collection[0].rule[0].destination_fqdn_tags) == "AzureKubernetesService"
    error_message = "AKS egress should use the AzureKubernetesService FQDN tag."
  }

  assert {
    condition     = length(azurerm_firewall_policy_rule_collection_group.aks[0].application_rule_collection[0].rule) == 2
    error_message = "Additional FQDNs should produce a second application rule."
  }
}

run "rejects_small_firewall_subnet" {
  command = plan

  variables {
    firewall = {
      name                  = "afw-hub-test-weu"
      subnet_address_prefix = "10.0.0.0/27"
    }
  }

  expect_failures = [var.firewall]
}

run "bastion_host" {
  command = plan

  variables {
    bastion = {
      name                  = "bas-hub-test-weu"
      subnet_address_prefix = "10.0.0.64/26"
    }
  }

  assert {
    condition     = length(azurerm_subnet.bastion) == 1 && azurerm_subnet.bastion[0].name == "AzureBastionSubnet"
    error_message = "Bastion must use the AzureBastionSubnet name."
  }

  assert {
    condition     = azurerm_bastion_host.this[0].copy_paste_enabled == false && azurerm_bastion_host.this[0].file_copy_enabled == false
    error_message = "Bastion clipboard and file copy should be disabled by default."
  }
}

run "vpn_gateway" {
  command = plan

  variables {
    vpn_gateway = {
      name                  = "vpng-hub-test-weu"
      subnet_address_prefix = "10.0.0.128/26"
      client_address_space  = ["172.16.201.0/24"]
      tenant_id             = "11111111-1111-1111-1111-111111111111"
    }
  }

  assert {
    condition     = length(azurerm_subnet.gateway) == 1 && azurerm_subnet.gateway[0].name == "GatewaySubnet"
    error_message = "The VPN gateway must use the GatewaySubnet name."
  }

  assert {
    condition = (
      azurerm_virtual_network_gateway.vpn[0].type == "Vpn" &&
      azurerm_virtual_network_gateway.vpn[0].vpn_type == "RouteBased" &&
      azurerm_virtual_network_gateway.vpn[0].sku == "VpnGw1" &&
      contains(azurerm_virtual_network_gateway.vpn[0].vpn_client_configuration[0].vpn_auth_types, "AAD") &&
      azurerm_virtual_network_gateway.vpn[0].vpn_client_configuration[0].aad_audience == "c632b3df-fb67-4d84-bdcf-b95ad541b5c8"
    )
    error_message = "The VPN gateway should be route-based VpnGw1 with Entra OpenVPN."
  }
}

run "rejects_small_gateway_subnet" {
  command = plan

  variables {
    vpn_gateway = {
      name                  = "vpng-hub-test-weu"
      subnet_address_prefix = "10.0.0.128/28"
      client_address_space  = ["172.16.201.0/24"]
      tenant_id             = "11111111-1111-1111-1111-111111111111"
    }
  }

  expect_failures = [var.vpn_gateway]
}
