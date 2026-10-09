## What

Installs the `maintenance` Azure CLI extension in the `local-exec` of `terraform_data.additional-dynamic-scope` (`mgt/core/update-manager/main.tf`), right before `az maintenance assignment create-or-update-subscription`.

## Why

AB#349451. The apply of the Prd 1 dynamic scope for the Bifrost subscription failed:

```
terraform_data.additional-dynamic-scope["prd1Bifrost"] (local-exec): ERROR: 'maintenance' is misspelled or not recognized by the system.
```

The pipeline agents (SCB shared UBC Linux) only include the `ad`, `azure-firewall` and `azure-devops` extensions (`CCoE-scb-infra-ubc`, `image-builder/linux/toolset-2404.json`). `az login` worked, so this is not a credentials issue.

## Impact

- +3 lines in `mgt/core/update-manager/main.tf`; only the new resource is changed.
- The failed resource is tainted, so the expected plan is **1 to add, 0 to change, 1 to destroy** (`terraform_data.additional-dynamic-scope["prd1Bifrost"]`). The destroy only removes it from the state.
- The apply creates the dynamic scope `Prd 1 - Monthly, Fourth Saturday at 02:00-DS` in `conp1glbsubbfrostaicx001` (2f267de7-e2c3-46e7-9d52-7adc9c97bd17).

## Follow-up

Add `maintenance` to `azExtensions` in the UBC image (`CCoE-scb-infra-ubc`) so the install step is no longer needed.

## Rollback

Revert this PR. If the dynamic scope was already created, delete it:
`az maintenance assignment delete-subscription --name "Prd 1 - Monthly, Fourth Saturday at 02:00-DS" --subscription 2f267de7-e2c3-46e7-9d52-7adc9c97bd17`
