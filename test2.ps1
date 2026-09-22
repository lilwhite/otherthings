az graph query -q "Resources | where type =~ 'microsoft.maintenance/maintenanceconfigurations' | project name, subscriptionId, resourceGroup, location, properties.maintenanceScope" --first 1000 -o table
az graph query -q "Resources | where type contains 'maintenance' | summarize count=count() by type | order by count desc" --first 1000 -o table

az graph query -q "Resources | where type contains 'maintenance' | summarize Total=count() by type | order by Total desc" --first 1000 -o table
az graph query -q "Resources | where type =~ 'microsoft.maintenance/maintenanceconfigurations' | project name, subscriptionId, resourceGroup, location, maintenanceScope=tostring(properties.maintenanceScope)" --first 1000 -o table
