# Dynamic scopes for maintenance configurations in additional subscriptions (see var.additional_dynamic_scopes).
resource "terraform_data" "additional-dynamic-scope" {
  for_each = var.additional_dynamic_scopes
  triggers_replace = [
    azurerm_maintenance_configuration.this[each.value.configuration].id,
    each.value.subscription
  ]
  provisioner "local-exec" {
    command = <<CMD
      az login --service-principal --username ${var.SP_client_id} --password ${var.SP_client_secret} --tenant ${var.tenant_id} --output none
      az maintenance assignment create-or-update-subscription \
        --maintenance-configuration-id "${azurerm_maintenance_configuration.this[each.value.configuration].id}" \
        --name "${azurerm_maintenance_configuration.this[each.value.configuration].name}-DS" \
        --filter-locations westeurope \
        --filter-resource-types "Microsoft.Compute/virtualMachines" \
        --filter-os-types Windows Linux \
        --filter-tags "{patchgroup:['${var.maintenance_configurations[each.value.configuration].include_tag}']}" \
        --filter-tags-operator Any \
        --subscription "${each.value.subscription}"
    CMD
  }
}
