# Dynamic scopes for maintenance configurations in additional subscriptions (see var.additional_dynamic_scopes).
resource "terraform_data" "additional-dynamic-scope" {
  provisioner "local-exec" {
    command = <<CMD
      az login --service-principal --username ${var.SP_client_id} --password ${var.SP_client_secret} --tenant ${var.tenant_id} --output none
      # The pipeline agents (UBC image) do not include the maintenance extension
      az extension add --name maintenance --upgrade --yes --only-show-errors
      # Pinned to 1.6.0: the version installed by default (1.2.1) has no subscription-level (dynamic scope) commands
      az extension add --source https://azcliprod.blob.core.windows.net/cli-extensions/maintenance-1.6.0-py3-none-any.whl --upgrade --yes --only-show-errors
      az maintenance assignment create-or-update-subscription \
