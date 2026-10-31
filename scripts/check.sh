#!/usr/bin/env bash
# Runs the repository quality gates: fmt, validate, mocked-provider tests and trivy.
# Usage: scripts/check.sh [dir ...]   (defaults to every module and example checked in CI)
set -euo pipefail

cd "$(dirname "$0")/.."

default_dirs=(
  modules/hub-network
  modules/network
  modules/aks
  modules/container-registry
  modules/key-vault
  modules/postgresql-flexible-server
  modules/storage-backend
  modules/storage-backend/examples/bootstrap
  modules/entra-app-registration
  modules/alerting
  modules/keycloak/clients
  modules/keycloak/roles
  modules/keycloak/groups
  modules/keycloak/identity-providers/google
  modules/keycloak/identity-providers/microsoft
  modules/keycloak/identity-providers/oidc
  modules/keycloak/examples/complete
  environments/dev
  environments/prod
  bootstrap/github-actions-identity
)
if [ $# -gt 0 ]; then dirs=("$@"); else dirs=("${default_dirs[@]}"); fi

export TF_PLUGIN_CACHE_DIR="${TF_PLUGIN_CACHE_DIR:-${HOME}/.terraform.d/plugin-cache}"
mkdir -p "$TF_PLUGIN_CACHE_DIR"

failed=()
for dir in "${dirs[@]}"; do
  echo "==> ${dir}"
  # set -e is ignored inside `if !`, so the steps are chained explicitly.
  if ! (
    cd "$dir" &&
      terraform fmt -check -recursive &&
      terraform init -backend=false -input=false >/dev/null &&
      terraform validate -no-color &&
      if [ -d tests ]; then terraform test -no-color; fi
  ); then
    failed+=("$dir")
  fi
done

if command -v tflint >/dev/null 2>&1; then
  echo "==> tflint"
  tflint --init >/dev/null
  for dir in "${dirs[@]}"; do
    tflint --chdir "$dir" --config "$PWD/.tflint.hcl" --minimum-failure-severity=warning || failed+=("tflint $dir")
  done
fi

if command -v terraform-docs >/dev/null 2>&1 && [ $# -eq 0 ]; then
  echo "==> terraform-docs"
  while IFS= read -r readme; do
    dir=$(dirname "$readme")
    terraform-docs -c .terraform-docs.yml --output-check "$dir" || failed+=("terraform-docs $dir")
  done < <(grep -rl --include=README.md --exclude-dir=.terraform BEGIN_TF_DOCS modules | sort)
fi

if command -v trivy >/dev/null 2>&1 && [ $# -eq 0 ]; then
  echo "==> trivy config"
  trivy config --ignorefile .trivyignore --severity MEDIUM,HIGH,CRITICAL --exit-code 1 -q . || failed+=("trivy")
fi

if [ ${#failed[@]} -gt 0 ]; then
  echo "FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "All checks passed."
