# Bootstrap

One-off Terraform that environments and CI depend on, but that is not itself an application
environment.

| Folder | Purpose |
|--------|---------|
| [`github-actions-identity`](github-actions-identity) | User-assigned identities and federated credentials for the GitHub Actions plan/apply workflow |

Remote state storage is bootstrapped separately: [`modules/storage-backend/examples/bootstrap`](../modules/storage-backend/examples/bootstrap).
