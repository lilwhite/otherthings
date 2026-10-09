## What

Adds `mgt/core/update-manager/versions.tf` pinning the `azurerm` provider to `>= 3.0.0,< 4.0.0`, the same constraint used in the other `mgt` folders (e.g. `mgt/core/network/versions.tf`).

## Why

AB#349451. This folder had no provider version constraint and no lock file, so `terraform init` installs the latest major version of `azurerm`. The latest major no longer supports `skip_provider_registration`, which is set in the shared `.env/variables-management.hcl`, so the plan fails:

```
Error: Unsupported argument
  on variables-management.tf line 63, in provider "azurerm":
  63:   skip_provider_registration = true
An argument named "skip_provider_registration" is not expected here.
```

This blocks the Prd 1 dynamic scope for the Bifrost subscription, already merged in <link to previous PR>.

## Impact

- Only adds `versions.tf`; no other files changed.
- Expected plan in `mgt/core/update-manager`: **1 to add, 0 to change, 0 to destroy**
  (`terraform_data.additional-dynamic-scope["prd1Bifrost"]`, from the previous PR, never applied).
- Verified locally with the real `variables-management.hcl`: `azurerm` v3.117.1 is installed and `terraform validate` succeeds.

## Rollback

Revert this PR.
