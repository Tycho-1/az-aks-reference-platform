# 0002. Hub-and-spoke with Azure Firewall for production egress

- Status: Accepted
- Date: 2026-09-30

## Context

By default an AKS cluster can reach any internet destination. Regulated environments need
egress to be restricted, logged and inspected. Microsoft's
[AKS egress guidance](https://learn.microsoft.com/azure/aks/limit-egress-traffic) and the baseline
architecture use Azure Firewall in a hub VNet, with a user-defined route (UDR) sending
`0.0.0.0/0` from the node subnet to the firewall.

A NAT gateway gives a static egress IP but no filtering. It is cheaper and simpler, which suits
development and test environments.

## Decision

- `environments/prod` uses hub-and-spoke. The `hub-network` module deploys a zone-redundant
  Azure Firewall (Standard, with Premium optional) and a firewall policy. Threat intelligence runs
  in `Deny` mode and the DNS proxy is enabled.
- AKS egress uses `outbound_type = "userDefinedRouting"`. The firewall allows only the AKS
  required endpoints (`AzureKubernetesService` FQDN tag, NTP, Azure Monitor, tunnel ports) plus
  explicitly listed FQDNs.
- The spoke's route table disables BGP propagation so learned routes can't bypass the firewall.
- `environments/dev` keeps NAT gateway egress. The `network` module supports both options,
  per subnet, and rejects using both on the same subnet.

## Consequences

- All egress is default-deny and logged to Log Analytics, and new destinations need a firewall
  rule change. That is intended, but it adds friction when onboarding new dependencies.
- Azure Firewall is a significant fixed cost. In an enterprise landing zone the hub is shared
  across many spokes and owned by a platform team; this repo deploys one so it is self-contained.
- The firewall becomes a dependency for cluster creation. Rules must exist before AKS
  provisions, or node bootstrapping fails.
