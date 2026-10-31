# 0005. Terraform stops at the cluster boundary

- Status: Accepted
- Date: 2026-09-30

## Context

Terraform's `kubernetes` and `helm` providers can install in-cluster software in the same run
that creates the cluster. This causes known problems:

- Provider configuration depends on attributes that don't exist until the cluster is created, so
  the first plan can't be complete.
- Replacing the cluster leaves the providers pointing at credentials that no longer exist.
- The Terraform state now holds the in-cluster resources as well.
- A private API server must be reachable from wherever Terraform runs.

## Decision

Terraform manages Azure resources only. In-cluster components (ingress, cert-manager, policies,
applications) are delivered by GitOps. The AKS module can configure the managed Flux extension
and its source and kustomizations (`gitops` input), so a new cluster reconciles its workloads
from Git without Terraform ever calling the Kubernetes API.

## Consequences

- A cluster can be recreated and rebuilds itself from Git. There are no provider chicken-and-egg
  problems.
- Terraform never needs network access to a private API server.
- Two tools and two change flows (Terraform for Azure, Git and Flux for the cluster), and drift
  inside the cluster shows up in Flux, not in `terraform plan`.
