# PostgreSQL Flexible Server module

Private Azure Database for PostgreSQL Flexible Server, kept separate from the AKS module because
the database has a different lifecycle, owner, and blast radius than the cluster. You can
recreate or upgrade the cluster without touching the data tier, and several clusters or apps can
share one server.

## What you get by default

| Area | Default |
|------|---------|
| Network | VNet-injected into a delegated subnet, **no public endpoint**, private DNS zone (created or supplied) |
| Authentication | **Entra ID only**; password auth is opt-in, and its password is passed through a write-only argument so it never lands in state |
| Resilience | Zone-redundant HA, 35-day PITR, optional geo-redundant backups, storage auto-grow, `ignore_changes` on zones so failovers don't cause drift |
| Operations | Custom maintenance window, connection logging, diagnostics to Log Analytics, `CanNotDelete` lock |
| Encryption (opt-in) | Customer-managed key with a dedicated identity; a second key and identity in the paired region for geo-redundant backups |

## Usage

```hcl
module "postgres" {
  source = "../../modules/postgresql-flexible-server"

  name                = "psql-platform-prod-weu"
  resource_group_name = azurerm_resource_group.data.name
  location            = "westeurope"

  delegated_subnet_id = module.network.subnet_ids["postgres"]
  private_dns_zone = {
    virtual_network_ids = { spoke = module.network.virtual_network_id }
  }

  entra_administrator = {
    object_id      = "<entra-group-object-id>"
    principal_name = "sg-platform-postgres-admins"
  }

  databases  = { app = {} }
  extensions = ["PG_TRGM"]

  log_analytics_workspace = { id = azurerm_log_analytics_workspace.this.id }
}
```

Applications on AKS should connect with **workload identity**: create a user-assigned identity with a
federated credential for the Kubernetes service account, create a matching Postgres role with
`pgaadauth_create_principal`, and use an Entra access token as the password.

For hub-and-spoke with central DNS, pass `private_dns_zone = { id = "<zone id>" }` instead of
having the module create a zone. Link that zone to the spoke VNet (the network module's
`private_dns_zone_links`).

Network requirements for the delegated subnet:

- Declare the `Microsoft.Storage` service endpoint. Azure adds it for WAL archiving, and without
  it Terraform would try to remove it.
- When egress goes through a firewall, allow TCP 443 to the `AzureActiveDirectory` service tag
  so that Entra authentication works.

Customer-managed key (Key Vault needs purge protection; RSA 2048/3072/4096):

```hcl
  geo_redundant_backup_enabled = true
  customer_managed_key = {
    key_vault_id     = module.key_vault.id
    key_vault_key_id = module.key_vault.keys["postgres"].versionless_id
    geo_backup = {
      location         = "northeurope"
      key_vault_id     = module.key_vault_paired.id
      key_vault_key_id = module.key_vault_paired.keys["postgres-geo-backup"].versionless_id
    }
  }
```

CMK is a creation-time setting.

## Key inputs

| Name | Description | Default |
|------|-------------|---------|
| `postgresql_version` | Major version | `17` |
| `sku_name` | `GP_`/`MO_` for HA; `B_` for dev | `GP_Standard_D2ds_v5` |
| `high_availability` | `{ mode, standby_availability_zone }` or `null` | `ZoneRedundant` |
| `backup_retention_days` | 7-35 | `35` |
| `geo_redundant_backup_enabled` | Creation-time only | `false` |
| `delegated_subnet_id` | Delegated subnet | required |
| `private_dns_zone` | Exactly one of `{ id }` (existing zone) or `{ virtual_network_ids }` (create and link) | required |
| `customer_managed_key` | `{ key_vault_id, key_vault_key_id, geo_backup }` | `null` |
| `entra_administrator` | Admin principal (use a group) | required |
| `password_auth_enabled` | Also allow local passwords | `false` |
| `administrator_login` / `administrator_password` | Only with password auth; password is ephemeral | `null` |
| `databases`, `extensions`, `server_parameters` | Data plane configuration | see `variables.tf` |
| `delete_lock_enabled` | `CanNotDelete` lock | `true` |

## Outputs

`id`, `name`, `fqdn`, `private_dns_zone_id`, `database_names`, `connection_string_template`.

<!-- BEGIN_TF_DOCS -->
## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| administrator\_login | Local administrator login. Only used when password\_auth\_enabled = true. | `string` | `null` | no |
| administrator\_password | Local administrator password. Ephemeral: it is passed through a write-only argument and never stored in state. | `string` | `null` | no |
| administrator\_password\_version | Increment to rotate administrator\_password (write-only values are not diffed). | `number` | `1` | no |
| auto\_grow\_enabled | Automatically grow storage before it runs out. | `bool` | `true` | no |
| backup\_retention\_days | Point-in-time restore window in days (7-35). | `number` | `35` | no |
| customer\_managed\_key | Encrypt data, logs and backups with a Key Vault key (RSA 2048-4096, vault with purge protection). Only possible at creation time. With geo-redundant backups, `geo_backup` must reference a key in a vault located in the paired region; the module creates a separate identity there. | ```object({ key_vault_id = string key_vault_key_id = string geo_backup = optional(object({ location = string key_vault_id = string key_vault_key_id = string })) })``` | `null` | no |
| databases | Databases to create, keyed by name. | ```map(object({ charset = optional(string, "UTF8") collation = optional(string, "en_US.utf8") }))``` | `{}` | no |
| delegated\_subnet\_id | Subnet delegated to Microsoft.DBforPostgreSQL/flexibleServers. The server gets no public endpoint. | `string` | n/a | yes |
| delete\_lock\_enabled | Add a CanNotDelete management lock to protect the server against accidental deletion. | `bool` | `true` | no |
| entra\_administrator | Entra ID principal (preferably a group) that administers the server. | ```object({ object_id = string principal_name = string principal_type = optional(string, "Group") })``` | n/a | yes |
| extensions | Extensions to allow-list via azure.extensions (e.g. ["PG\_TRGM", "POSTGIS"]). They still need CREATE EXTENSION per database. | `list(string)` | `[]` | no |
| geo\_redundant\_backup\_enabled | Replicate backups to the paired region. Can only be set at creation time. | `bool` | `false` | no |
| high\_availability | High availability. ZoneRedundant places a hot standby in another zone (recommended for production; not available on Burstable SKUs). Null disables HA. | ```object({ mode = optional(string, "ZoneRedundant") standby_availability_zone = optional(string, "2") })``` | `{}` | no |
| location | Azure region. | `string` | n/a | yes |
| log\_analytics\_workspace | Send server logs and metrics to Log Analytics. Null disables diagnostics. | ```object({ id = string })``` | `null` | no |
| maintenance\_window | Custom maintenance window (UTC). day\_of\_week: 0 = Sunday. | ```object({ day_of_week = optional(number, 0) start_hour = optional(number, 2) start_minute = optional(number, 0) })``` | `{}` | no |
| name | Globally unique server name (e.g. psql-platform-prod-weu). | `string` | n/a | yes |
| password\_auth\_enabled | Allow PostgreSQL password authentication in addition to Entra ID. Keep false unless a client cannot use Entra tokens. | `bool` | `false` | no |
| postgresql\_version | Major PostgreSQL version. | `string` | `"17"` | no |
| private\_dns\_zone | Private DNS. Either pass an existing zone via `id` (typical for hub-and-spoke with central DNS), or let the module create `<name>.private.postgres.database.azure.com` linked to `virtual_network_ids`. | ```object({ id = optional(string) virtual_network_ids = optional(map(string)) })``` | n/a | yes |
| resource\_group\_name | Name of an existing resource group. | `string` | n/a | yes |
| server\_parameters | Additional server parameters, keyed by parameter name. | `map(string)` | ```{ "log_checkpoints": "on", "log_connections": "on", "log_disconnections": "on" }``` | no |
| sku\_name | SKU in <tier>\_<size> form. General Purpose (GP\_) or Memory Optimized (MO\_) is required for high availability. | `string` | `"GP_Standard_D2ds_v5"` | no |
| storage\_mb | Allocated storage in MB. With auto-grow enabled this is the starting size. | `number` | `65536` | no |
| tags | Tags applied to all resources. | `map(string)` | `{}` | no |
| zone | Availability zone of the primary server. | `string` | `"1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| connection\_string\_template | libpq connection string without credentials. With Entra auth, the password is an access token for https://ossrdbms-aad.database.windows.net. |
| database\_names | Names of the databases created by the module. |
| fqdn | Private FQDN of the server. |
| id | Resource ID of the server. |
| name | Name of the server. |
| private\_dns\_zone\_id | ID of the private DNS zone used by the server. |
<!-- END_TF_DOCS -->
