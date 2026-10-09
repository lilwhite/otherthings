# Dynamic scopes for the maintenance configurations in subscriptions other than the one set in
# var.maintenance_configurations (for example landing zone workload subscriptions).
# "configuration" must be a key of var.maintenance_configurations.
variable "additional_dynamic_scopes" {
  description = "Additional dynamic scopes for maintenance configurations in other subscriptions"
  type = map(object({
    configuration = string
    subscription  = string
  }))
  default = {
    # Bifrost (conp1glbsubbfrostaicx001)
    prd1Bifrost = {
      configuration = "prd1"
      subscription  = "2f267de7-e2c3-46e7-9d52-7adc9c97bd17"
    }
  }
}
