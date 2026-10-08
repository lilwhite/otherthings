fix(backup): protect conp1weugvmw002 with a Recovery Services vault in mgct



## Description
**What:** Adds a Recovery Services vault, a daily "high" VM backup policy and backup protection for VM `conp1weugvmw002` (bastion2) in subscription conp1glbsubplatlzmgct001.

**Why:** The VM has no backup. The legacy backup model (tag `backupgroup` + DINE assignments `SA2-DN-VMS-Backup*` in CCoE-scb-tf-main) only covers the legacy subscriptions, and there is no Recovery Services vault in the mgct subscription. Azure Backup requires the vault in the same subscription and region as the VM.

**How:** In `management/backup`:
- `locals.tf`: new locals `recovery_services_vault_name` and `instant_restore_app_acronym`.
- `data.tf` (new): data source for VM `conp1weugvmw002`.
- `main.tf`: new resource group for instant restore snapshots (no lock), `azurerm_recovery_services_vault.this` (GRS, soft delete), `azurerm_backup_policy_vm.high` (daily 22:00 UTC, 7d/4w/12m/1y, same as legacy high) and `azurerm_backup_protected_vm.bastion2`.
The existing Data Protection backup vault is not changed.

## Related work item
<!-- Link to the ticket of the case -->

## Testing
<!-- Link to the manual pipeline run on branch fix/backup-bastion2-mgct (Terraform Plan). Expected: only additions, 0 to change, 0 to destroy. -->

## Relevant docs
- [ ] I have created or updated relevant documentation for changes in this pull request.

## Additional Notes
- `management-backup.yaml` has `pr: none`, so the plan was run manually on the branch and the apply approval was rejected.
- Rollback: revert this PR. Backup data remains in soft delete for 14 days.
- Follow-up: bastion1 (`conp1weugvmw001`) and DNS VM (`conp1weudnsw001`) are also unprotected.

## Checklist before requesting review
- [ ] Terraform Plan ran successfully


