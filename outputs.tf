########################################################
#
#                 Outputs
#
########################################################

output "region_source" {
  description = "The source Azure region with spaces replaced by hyphens."
  value       = local.region.source
}

output "region_target" {
  description = "The target Azure region with spaces replaced by hyphens."
  value       = local.region.target
}

output "vault_name" {
  description = "The name of the recovery services vault."
  value       = local.recovery_services_vault_name
}

output "site_recovery_fabric_name_source" {
  description = "The name of the source site recovery fabric."
  value       = azurerm_site_recovery_fabric.fabric[local.region.source].name
}

output "site_recovery_fabric_name_target" {
  description = "The name of the target site recovery fabric."
  value       = azurerm_site_recovery_fabric.fabric[local.region.target].name
}

output "protection_container_name_source" {
  description = "The name of the source protection container."
  value       = azurerm_site_recovery_protection_container.source.name
}

output "protection_container_name_target" {
  description = "The name of the target protection container."
  value       = azurerm_site_recovery_protection_container.target.name
}

output "replication_policy_ids" {
  description = "The id of the replication policies."
  value = {
    for replication_policy in var.virtual_machine_replication_policies : replication_policy.name => {
      resource_id = azurerm_site_recovery_replication_policy.policy[replication_policy.name].id
    }
  }
}

output "protection_container_mapping_name" {
  description = "The name of the protection container mapping."
  value       = {
    for replication_policy in var.virtual_machine_replication_policies : replication_policy.name => {
      resource_id = azurerm_site_recovery_protection_container_mapping.mapping[replication_policy.name].id
    }
  }
}

output "network_mapping_names" {
  description = "A map containing VM names and their associated network mapping names."
  value       = local.network_mapping_names
}

output "capacity_reservation_group_name" {
  description = "The name of the capacity reservation group."
  value       = coalesce(var.capacity_reservation_group_name, "crg-${random_string.unique_suffix[0].result}")
}

output "shared_capacity_reservation_group_id" {
  description = "The ID of the shared capacity reservation group, if created."
  value       = var.capacity_reservation_group_creation_enabled ? azurerm_capacity_reservation_group.shared_cr_group[0].id : ""
  sensitive   = false
}

output "replicated_vm_names" {
  description = "A map containing VM names and their associated replicated VM names."
  value       = { for vm_name, vm in var.replicated_virtual_machines : vm_name => vm_name }
}

output "storage_account_name" {
  description = "The name of the staging storage account for replication."
  value       = var.storage_account_creation_enabled ? "sa${random_string.storage_account_name[0].result}" : var.storage_account_name
}

output "replicated_vms_info" {
  description = "Information about the replicated VMs."
  value = [for vm_name in keys(var.replicated_virtual_machines) : {
    vm_name                              = vm_name
    replicated_vm_id                     = azurerm_site_recovery_replicated_vm.replicated_vm[vm_name].id
    target_capacity_reservation_group_id = azurerm_site_recovery_replicated_vm.replicated_vm[vm_name].target_capacity_reservation_group_id
  }]
}

output "individual_capacity_reservation_ids" {
  description = "The IDs of individual capacity reservations if they are created per VM."
  value = {
    for vm_name, vm in var.replicated_virtual_machines :
    vm_name => (vm.create_capacity_reservation == true && can(azurerm_capacity_reservation.per_vm[vm_name]))
    ? azurerm_capacity_reservation.per_vm[vm_name].id
    : ""
  }
  sensitive = false
}
