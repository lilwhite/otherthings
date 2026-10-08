# Consultas de Azure Resource Graph: caso backup conp1weugvmw002

- **Dónde:** portal → Resource Graph Explorer. Ámbito: todo el tenant / todas las suscripciones.
- **Salida:** *Download as CSV*. Guarda los ficheros en `evidencias/` con el nombre indicado (`Q1-suscripciones.csv`, …).
- **Permiso:** Reader. Todas las consultas son de solo lectura.
- Si alguna da error o una columna sale vacía, apunta el error y sigue con las demás.

## Q1 — Suscripciones (nombre ↔ ID)

```kql
ResourceContainers
| where type =~ 'microsoft.resources/subscriptions'
| project subscriptionName = name, subscriptionId, state = tostring(properties.state)
| order by subscriptionName asc
```

## Q2 — Todas las VMs con sus tags de backup

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| project subscriptionId, resourceGroup, name, location,
          osType = tostring(properties.storageProfile.osDisk.osType),
          vmSize = tostring(properties.hardwareProfile.vmSize),
          powerState = tostring(properties.extended.instanceView.powerState.code),
          backupgroup = tostring(tags.backupgroup),
          repository = tostring(tags.repository),
          environment = tostring(tags.environment),
          id
| order by subscriptionId asc, name asc
```

## Q3 — Recovery Services vaults

```kql
Resources
| where type =~ 'microsoft.recoveryservices/vaults'
| project subscriptionId, resourceGroup, name, location,
          sku = tostring(sku.name),
          storageRedundancy = tostring(properties.redundancySettings.standardTierStorageRedundancy),
          crossRegionRestore = tostring(properties.redundancySettings.crossRegionRestore),
          softDelete = tostring(properties.securitySettings.softDeleteSettings.softDeleteState),
          immutability = tostring(properties.securitySettings.immutabilitySettings.state),
          publicNetworkAccess = tostring(properties.publicNetworkAccess),
          privateEndpoints = array_length(properties.privateEndpointConnections),
          repository = tostring(tags.repository),
          id
| order by subscriptionId asc, name asc
```

## Q4 — VMs protegidas (backup items)

```kql
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
| where tostring(properties.workloadType) =~ 'VM'
| project vaultSubscriptionId = subscriptionId,
          vault = tostring(split(id, '/')[8]),
          vmId = tolower(tostring(properties.sourceResourceId)),
          friendlyName = tostring(properties.friendlyName),
          policy = tostring(properties.policyName),
          protectionState = tostring(properties.protectionState),
          protectionStatus = tostring(properties.protectionStatus),
          lastBackupStatus = tostring(properties.lastBackupStatus),
          lastBackupTime = tostring(properties.lastBackupTime),
          healthStatus = tostring(properties.healthStatus)
| order by vault asc, friendlyName asc
```

## Q5 — Políticas de backup de los vaults

```kql
RecoveryServicesResources
| where type =~ 'microsoft.recoveryservices/vaults/backuppolicies'
| project subscriptionId, resourceGroup,
          vault = tostring(split(id, '/')[8]),
          policy = name,
          managementType = tostring(properties.backupManagementType),
          policyType = tostring(properties.policyType),
          schedule = tostring(properties.schedulePolicy),
          retention = tostring(properties.retentionPolicy),
          protectedItems = toint(properties.protectedItemsCount)
| order by vault asc, policy asc
```

## Q6 — Data Protection backup vaults (blobs, discos, etc.)

```kql
Resources
| where type =~ 'microsoft.dataprotection/backupvaults'
| project subscriptionId, resourceGroup, name, location,
          redundancy = tostring(properties.storageSettings[0].type),
          repository = tostring(tags.repository)
```

## Q7 — Asignaciones de Azure Policy relacionadas con backup

Sirve para comprobar si alguna política DINE configura backup fuera del código.

```kql
PolicyResources
| where type =~ 'microsoft.authorization/policyassignments'
| where tolower(tostring(properties.displayName)) contains 'backup'
     or tolower(tostring(properties.policyDefinitionId)) contains 'backup'
     or tolower(tostring(properties.policyDefinitionId)) has_any ('09ce66bc-1220-4153-8104-e3f51c936913','345fa903-145c-4fe1-8bcd-93ec2adccde8','98d0b9f8-fd90-49c9-88e2-d3baf3b0dd86')
| project name, displayName = tostring(properties.displayName),
          scope = tostring(properties.scope),
          policyDefinitionId = tostring(properties.policyDefinitionId),
          enforcement = tostring(properties.enforcementMode)
```

## Q8 (opcional) — VMs con su estado de backup en una sola tabla

Si Resource Graph rechaza el `join` entre tablas, no pasa nada: Q2 + Q4 dan lo mismo y el cruce lo hago yo.

```kql
Resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend vmId = tolower(id)
| project vmId, subscriptionId, resourceGroup, name, location, backupgroup = tostring(tags.backupgroup)
| join kind=leftouter (
    RecoveryServicesResources
    | where type =~ 'microsoft.recoveryservices/vaults/backupfabrics/protectioncontainers/protecteditems'
    | where tostring(properties.workloadType) =~ 'VM'
    | project vmId = tolower(tostring(properties.sourceResourceId)),
              vault = tostring(split(id, '/')[8]),
              policy = tostring(properties.policyName),
              lastBackupStatus = tostring(properties.lastBackupStatus)
) on vmId
| project subscriptionId, resourceGroup, name, location, backupgroup, vault, policy, lastBackupStatus
| order by subscriptionId asc, name asc
```
