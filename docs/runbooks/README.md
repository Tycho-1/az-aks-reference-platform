# Runbooks

Operational procedures are not written yet. This folder is the place for them.

The platform already has the settings these procedures will use. The steps for an operator
are still missing:

| Runbook | What it will cover | Already in the modules |
|---------|--------------------|------------------------|
| Cluster upgrades | How to move the Kubernetes minor, and what the automatic channels do between those moves | `automatic_upgrade_channel`, `node_os_upgrade_channel`, and the maintenance windows on `modules/aks` |
| PostgreSQL restore and DR | Point-in-time restore, and how the paired-region backup key is used | Geo-redundant backups and the paired-region CMK when `postgres_enabled` is true |
| CMK rotation or revocation | Rotating or disabling a customer-managed key, and what that does to disks, etcd, and ACR | Key Vault keys created by `modules/key-vault` |
| Break-glass cluster access | Reaching a private API when the normal path is down | `az aks command invoke`, Bastion, and the optional hub VPN (`vpn_gateway_enabled`) |

Do not treat this page as a procedure. None of these have been rehearsed as runbooks.
