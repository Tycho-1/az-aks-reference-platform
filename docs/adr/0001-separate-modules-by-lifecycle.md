# 0001. Separate modules by lifecycle

- Status: Accepted
- Date: 2026-09-30

## Context

The original AKS module created the cluster and its PostgreSQL database together. The two have
different lifecycles and owners. Clusters are rebuilt or replaced (blue/green upgrades,
networking changes that force replacement), while the database holds state that must survive
all of that. A single module also means one blast radius: a change to a node pool plans against
the database, and destroying the cluster destroys the data.

The [AKS baseline architecture](https://learn.microsoft.com/azure/architecture/reference-architectures/containers/aks/baseline-aks)
and [Azure Verified Modules](https://azure.github.io/Azure-Verified-Modules/) both model the
cluster, networking, registry, key management and data services as independent resources.

## Decision

Each Azure capability is its own module: `hub-network`, `network`, `aks`, `container-registry`,
`key-vault`, `postgresql-flexible-server`, `storage-backend`. The root configurations in
`environments/` compose them and place each layer in its own resource group
(`connectivity`, `network`, `security`, `aks`, `data`, `ops`).

Modules communicate only through inputs and outputs (IDs), never by reading each other's
resources.

## Consequences

- The cluster can be replaced without touching the database, registry or keys.
- Teams can own layers separately. In a larger organisation the layers move into separate
  state files with little change.
- Several clusters or applications can share one database server or registry.
- The root configuration has more wiring (IDs passed between modules), and ordering has to
  be made explicit with outputs that `depends_on` their associations.
