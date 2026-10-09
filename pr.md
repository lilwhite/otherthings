## What
Adds `var.additional_dynamic_scopes` and `terraform_data.additional-dynamic-scope` in `mgt/core/update-manager` to create the dynamic scope of an existing maintenance configuration in other subscriptions.
First entry: **Prd 1** in `conp1glbsubbfrostaicx001` (2f267de7-e2c3-46e7-9d52-7adc9c97bd17).

## Why
AB#349451. Each maintenance configuration only has a dynamic scope in one legacy subscription, so VMs in landing zone subscriptions (Bifrost) are never patched, even with the right `patchgroup` tag.

## Impact
- Plan: 1 to add, 0 to change, 0 to destroy (`terraform_data.additional-dynamic-scope["prd1Bifrost"]`).
- Existing maintenance configurations and dynamic scopes are not changed.
- The VM tag is changed to `prd 1` in a separate PR in cloudplatform-application-workload-bifrost.

## Rollback
Revert this PR and delete the assignment:
`az maintenance assignment delete-subscription --name "Prd 1 - Monthly, Fourth Saturday at 02:00-DS" --subscription 2f267de7-e2c3-46e7-9d52-7adc9c97bd17`
