#!/usr/bin/env bash
# Builds the Flux entry points and checks them against Kubernetes 1.36 schemas
# and the Flux CRD schemas. Requires kustomize (or kubectl) and kubeconform.
set -euo pipefail

cd "$(dirname "$0")/.."

if command -v kustomize >/dev/null 2>&1; then
  build() { kustomize build "$1"; }
elif command -v kubectl >/dev/null 2>&1; then
  build() { kubectl kustomize "$1"; }
else
  echo "kustomize or kubectl is required" >&2
  exit 1
fi

if ! command -v kubeconform >/dev/null 2>&1; then
  echo "kubeconform is required" >&2
  exit 1
fi

# These two directories are what Flux reconciles. The sample-api base is included
# by apps/production, so it is not built on its own.
dirs=(
  gitops/apps/production
  gitops/infrastructure/controllers
)

for dir in "${dirs[@]}"; do
  echo "==> ${dir}"
  build "$dir" | kubeconform -strict -summary -kubernetes-version 1.36.0 \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
done
