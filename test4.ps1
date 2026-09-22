$sub = "e76d4c12-0b6b-4a47-a714-fa2302974203"
$rg  = "scb-core-mgt-updatemgr-rg"

az account set --subscription $sub

az maintenance configuration list --resource-group $rg --query "[?starts_with(name, 'Dev ') || starts_with(name, 'Mgt ') || starts_with(name, 'Prd ')].{Name:name, ID:id, Scope:maintenanceScope, StartDateTime:startDateTime, RecurEvery:recurEvery, Duration:duration, TimeZone:timeZone}" -o table



------


az maintenance configuration show --resource-group $rg --resource-name "Prd 1 - Monthly, Fourth Saturday at 02:00" -o json


------


az maintenance assignment list-subscription --maintenance-configuration-id "/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.Maintenance/maintenanceConfigurations/Prd 1 - Monthly, Fourth Saturday at 02:00" -o json

------

az maintenance assignment -h

az maintenance assignment list-subscription -h
