# 0004. Private by default, with central private DNS in the hub

- Status: Accepted
- Date: 2026-09-30

## Context

A public endpoint, even one behind an IP allow-list, is still reachable from the internet and
depends on the allow-list staying correct. Azure's security baselines for AKS, ACR, Key Vault and
PostgreSQL recommend private endpoints or VNet injection.

Private endpoints only work when DNS resolves the service name to the private IP. Per-spoke DNS
zones fragment resolution and break when spokes need each other's services. Microsoft's
[private endpoint DNS guidance](https://learn.microsoft.com/azure/private-link/private-endpoint-dns-integration)
recommends central zones in the hub.

## Decision

- Public network access defaults to off in every module. It turns on only when the caller
  supplies `allowed_ip_ranges`, and then with a default-deny firewall.
- In production, ACR and Key Vault use private endpoints, PostgreSQL is VNet-injected into a
  delegated subnet, and AKS is a private cluster with API server VNet integration.
- The private DNS zones (`privatelink.azurecr.io`, `privatelink.vaultcore.azure.net`,
  `privatelink.<region>.azmk8s.io`, `private.postgres.database.azure.com`) live in the hub.
  Spokes use the firewall DNS proxy as their DNS server. A zone is linked directly to a spoke
  only when the service requires it (PostgreSQL); AKS links its own zone.

## Consequences

- No data-plane endpoint of the platform is reachable from the internet.
- Terraform and CI must run from inside the network (self-hosted runner) or temporarily allow
  their IP, because Key Vault key creation and image pushes are data-plane operations.
- Operators reach the private API server through `az aks command invoke`, Azure Bastion or a
  jump host.
