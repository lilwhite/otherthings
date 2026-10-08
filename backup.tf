# Resource group for the instant restore snapshots (restore point collections) of the VM backups.
# It has no lock because Azure Backup deletes expired restore points in it.
module "resource_group_instant_restore" {
  source = "git::https://github.com/santander-group-scfno/CCoE-Public-scb-module-resource-group.git?ref=v1.0.5"

  environment               = var.environment
  function                  = local.function
  app_acronym               = local.instant_restore_app_acronym
  apply_resource_group_lock = false

  tags = local.tags
}

# Recovery Services vault for the backups of the virtual machines in the management subscription.
resource "azurerm_recovery_services_vault" "this" {
  name                         = local.recovery_services_vault_name
  location                     = module.resource-group.rg_location
  resource_group_name          = module.resource-group.rg_name
  sku                          = "Standard"
  storage_mode_type            = "GeoRedundant"
  cross_region_restore_enabled = false
  soft_delete_enabled          = true

  tags = merge(local.tags, {
    name = local.recovery_services_vault_name
  })
}

# Daily VM backup policy equivalent to the legacy "high" policies in CCoE-scb-tf-main (mgt/core/backup).
resource "azurerm_backup_policy_vm" "high" {
  name                           = "${local.recovery_services_vault_name}-high"
  resource_group_name            = module.resource-group.rg_name
  recovery_vault_name            = azurerm_recovery_services_vault.this.name
  timezone                       = "UTC"
  policy_type                    = "V1"
  instant_restore_retention_days = 2

  # Azure Backup appends "1" to the prefix, so the trailing "1" is removed to target the resource group above.
  instant_restore_resource_group {
    prefix = trimsuffix(module.resource_group_instant_restore.rg_name, "1")
  }

  backup {
    frequency = "Daily"
    time      = "22:00"
  }

  retention_daily {
    count = 7
  }

  retention_weekly {
    count    = 4
    weekdays = ["Sunday"]
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }

  retention_yearly {
    count    = 1
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

# Backup protection for the bastion VM conp1weugvmw002 (bastion2 in management/bast).
resource "azurerm_backup_protected_vm" "bastion2" {
  resource_group_name = module.resource-group.rg_name
  recovery_vault_name = azurerm_recovery_services_vault.this.name
  source_vm_id        = data.azurerm_virtual_machine.bastion2.id
  backup_policy_id    = azurerm_backup_policy_vm.high.id
}
