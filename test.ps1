az graph query -q "Resources | where type =~ 'microsoft.maintenance/configurationassignments' | project name, subscriptionId, resourceGroup, location, properties" --first 100 -o table
