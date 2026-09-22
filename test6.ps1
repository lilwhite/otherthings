$query = @'
maintenanceresources
| where type =~ 'microsoft.maintenance/configurationassignments'
| project id, name, subscriptionId, properties
| take 5
'@

az graph query -q $query --first 5 -o json
