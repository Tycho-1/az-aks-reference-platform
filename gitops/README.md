# GitOps content

In-cluster configuration reconciled by the AKS Flux extension. Terraform stops at the cluster
boundary ([ADR 0005](../docs/adr/0005-terraform-stops-at-the-cluster-boundary.md)): it installs
Flux and points it at this folder, and everything below is delivered from Git.

```
gitops/
├── infrastructure/controllers/   # Flux Kustomization "infrastructure"
│   └── cert-manager.yaml         #   HelmRepository + HelmRelease, HA with PDBs
└── apps/                         # Flux Kustomization "apps" (depends on infrastructure)
    ├── base/sample-api/          #   hardened reference workload
    └── production/               #   environment overlay: image, identity, database host
```

Enable it with `gitops_repository_url` in [`environments/prod`](../environments/prod). Terraform
also adds the Git host and the cert-manager chart and image registries to the firewall allow-list.

## Sample API

The workload shows what the platform expects from every application:

| Concern | How |
|---------|-----|
| Azure access | Workload identity: the `sample-api` service account is federated to a managed identity created in `environments/prod/apps.tf`. No secrets |
| Database | PostgreSQL with Entra authentication. The pod fetches a token as its password, and the role is created with `pgaadauth_create_principal` (see the `sample_api_workload_identity` output) |
| Images | Pulled from the private ACR (`az acr import`), never directly from public registries |
| Pod security | Namespace enforces the `restricted` Pod Security Standard; non-root, read-only root filesystem, no capabilities, `RuntimeDefault` seccomp |
| Network | Default-deny NetworkPolicies (enforced by Cilium). Only DNS, PostgreSQL and HTTPS egress are allowed, and the firewall filters HTTPS by FQDN |
| Availability | 3+ replicas spread across zones, PDB, HPA, readiness/liveness probes, zero-downtime rolling updates |
| Guardrails | ResourceQuota and LimitRange in the namespace |

The container is [podinfo](https://github.com/stefanprodan/podinfo), a small demo API used as a
stand-in. Replace the image with your own service; the rest of the manifests still apply.

## Onboarding a new environment

1. Copy `apps/production` to `apps/<env>`, and set the image registry, the identity client ID
   and the database host from that environment's Terraform outputs.
2. Point that environment's `gitops.kustomizations.apps.path` at the new overlay.

[`.github/workflows/gitops.yml`](../.github/workflows/gitops.yml) builds both Flux entry points
and checks the result with kubeconform when this folder changes. It does not apply Azure.
Locally, with `kustomize` or `kubectl` and `kubeconform` installed:

```sh
scripts/check-gitops.sh
```
