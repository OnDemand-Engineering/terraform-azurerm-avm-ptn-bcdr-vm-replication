########################################################
#
#                 Local Variables definition
#
#######################################################
locals {
  region = {
    source = replace(var.source_location, " ", "-")
    target = replace(var.target_location, " ", "-")
  }

  recovery_services_vault_name = var.recovery_services_vault_creation_enabled ? azurerm_recovery_services_vault.vault[0].name : var.recovery_services_vault_name

  network_mapping_names = { for vm_name in keys(var.replicated_virtual_machines) : vm_name => "${vm_name}-network-mapping" }
}

########################################################
#
#                 Data sources
#
#######################################################

data "azurerm_subscription" "current" {}
data "azapi_client_config" "current" {}

resource "random_string" "unique_suffix" {
  count   = var.capacity_reservation_group_creation_enabled ? 1 : 0
  length  = 8
  numeric = true
  special = false
  upper   = false
}

########################################################
#
#               Recovery Infrastructure
#
#######################################################

# recovery services vault
resource "azurerm_recovery_services_vault" "vault" {
  count = var.recovery_services_vault_creation_enabled ? 1 : 0
  name  = var.recovery_services_vault_name

  location            = var.target_location
  resource_group_name = var.recovery_services_vault_resource_group_name
  sku                 = "Standard"
  tags                = var.tags
}

# replication policies
resource "azurerm_site_recovery_replication_policy" "policy" {
  for_each = {
    for replication_policy in var.virtual_machine_replication_policies : replication_policy.name => replication_policy
  }

  name                                                 = each.value.name
  resource_group_name                                  = var.recovery_services_vault_resource_group_name
  recovery_vault_name                                  = local.recovery_services_vault_name
  recovery_point_retention_in_minutes                  = 60 * 24 * each.value.recovery_point_retention_in_days
  application_consistent_snapshot_frequency_in_minutes = 60 * each.value.application_consistent_snapshot_frequency_in_hours
}

# fabric
resource "azurerm_site_recovery_fabric" "fabric" {
  for_each = {
    for region_key, region in distinct([local.region.source, local.region.target]) : region => {
      region_key = region_key
      region     = region
    }
  }

  name                = var.azurerm_site_recovery_fabric_name != null ? var.azurerm_site_recovery_fabric_name[each.value.region_key] : "asr-a2a-default-${each.value.region}"
  resource_group_name = var.recovery_services_vault_resource_group_name
  recovery_vault_name = local.recovery_services_vault_name
  location            = each.value.region
}

# protection containers
resource "azurerm_site_recovery_protection_container" "source" {
  name                 = var.azurerm_site_recovery_protection_container.source
  resource_group_name  = var.recovery_services_vault_resource_group_name
  recovery_vault_name  = local.recovery_services_vault_name
  recovery_fabric_name = azurerm_site_recovery_fabric.fabric[local.region.source].name
}

resource "azurerm_site_recovery_protection_container" "target" {
  name                 = var.azurerm_site_recovery_protection_container.target
  resource_group_name  = var.recovery_services_vault_resource_group_name
  recovery_vault_name  = local.recovery_services_vault_name
  recovery_fabric_name = azurerm_site_recovery_fabric.fabric[local.region.target].name
}

# protection container mapping
resource "azurerm_site_recovery_protection_container_mapping" "mapping" {
  for_each = {
    for replication_policy in var.virtual_machine_replication_policies : replication_policy.name => replication_policy
  }

  name                                      = "${local.region.source}-${local.region.target}-${each.value.name}"
  resource_group_name                       = var.recovery_services_vault_resource_group_name
  recovery_vault_name                       = local.recovery_services_vault_name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.fabric[local.region.source].name
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.source.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.target.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy[each.value.name].id

  dynamic "automatic_update" {
    for_each = var.automatic_update ? [1] : []
    content {
      enabled               = var.automatic_update
      automation_account_id = var.automation_account_id
      authentication_type   = "SystemAssignedIdentity"
    }
  }
}

resource "random_string" "storage_account_name" {
  count = var.storage_account_creation_enabled ? 1 : 0

  length  = 16
  special = false
  upper   = false
  numeric = true
  lower   = true
}

resource "azurerm_storage_account" "staging" {
  count = var.storage_account_creation_enabled ? 1 : 0

  name                     = coalesce(var.storage_account_name, "sa${random_string.storage_account_name[0].result}")
  resource_group_name      = coalesce(var.storage_account_resource_group_name, var.recovery_services_vault_resource_group_name)
  location                 = var.source_location
  account_tier             = "Standard"
  account_replication_type = var.staging_replication_type
}

resource "azurerm_site_recovery_network_mapping" "network_mapping" {
  # Only create network mapping if the source and target locations are different
  count = var.source_location != var.target_location ? length(local.network_mapping_names) : 0

  name                        = local.network_mapping_names[count.index]
  resource_group_name         = azurerm_recovery_services_vault.vault[0].resource_group_name
  recovery_vault_name         = azurerm_recovery_services_vault.vault[0].name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.fabric[local.region.source].name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.fabric[local.region.target].name
  source_network_id           = var.replicated_virtual_machines[local.network_mapping_names[count.index]].source_network_id
  target_network_id           = var.replicated_virtual_machines[local.network_mapping_names[count.index]].target_network_id
}

########################################################
#
#                Capacity Reservation
#
#######################################################

resource "azurerm_capacity_reservation_group" "shared_cr_group" {
  count = var.capacity_reservation_group_creation_enabled ? 1 : 0

  name                = coalesce(var.capacity_reservation_group_name, "crg-${random_string.unique_suffix[0].result}")
  location            = var.target_location
  resource_group_name = var.recovery_services_vault_resource_group_name
  tags                = var.tags
}


resource "azurerm_capacity_reservation" "per_vm" {
  for_each                      = { for vm in var.replicated_virtual_machines : vm.key => vm.virtual_machine_resource_id if vm.capacity_reservation_creation_enabled == true }
  name                          = "${each.key}-capacity-reservation"
  capacity_reservation_group_id = var.existing_capacity_reservation_group_id != "" ? var.existing_capacity_reservation_group_id : azurerm_capacity_reservation_group.shared_cr_group[0].id

  sku {
    name     = each.value.capacity_reservation_sku
    capacity = 1
  }

  tags = var.tags
}

########################################################
#
#                Replicated VM
#
#######################################################


resource "azurerm_site_recovery_replicated_vm" "replicated_vm" {
  for_each = var.replicated_virtual_machines

  name                                      = provider::azapi::parse_resource_id("Microsoft.Compute/virtualMachines", each.value.virtual_machine_resource_id).name
  resource_group_name                       = var.recovery_services_vault_resource_group_name
  recovery_vault_name                       = local.recovery_services_vault_name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.fabric[local.region.source].name
  source_vm_id                              = each.value.virtual_machine_resource_id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.policy[each.value.replication_policy_name].id
  target_resource_group_id                  = each.value.target_resource_group_id
  target_recovery_fabric_id                 = azurerm_site_recovery_fabric.fabric[local.region.target].id
  target_recovery_protection_container_id   = azurerm_site_recovery_protection_container.target.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.source.name
  target_capacity_reservation_group_id      = each.value.capacity_reservation_creation_enabled == true ? azurerm_capacity_reservation.per_vm[each.key].capacity_reservation_group_id : null
  target_availability_set_id                = each.value.target_availability_set_id
  target_zone                               = each.value.target_zone
  target_edge_zone                          = each.value.target_edge_zone
  target_network_id                         = each.value.target_network_id
  target_proximity_placement_group_id       = each.value.target_proximity_placement_group_id
  target_boot_diagnostic_storage_account_id = each.value.target_boot_diagnostic_storage_account_id
  target_virtual_machine_scale_set_id       = each.value.target_virtual_machine_scale_set_id
  test_network_id                           = each.value.test_network_id
  multi_vm_group_name                       = each.value.multi_vm_group_name

  dynamic "managed_disk" {
    for_each = { for disk in each.value.managed_disks : disk.disk_id => disk }

    content {
      disk_id                       = managed_disk.value.disk_id
      staging_storage_account_id    = var.storage_account_creation_enabled ? azurerm_storage_account.staging[0].id : provider::azapi::build_resource_id("/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${coalesce(var.storage_account_resource_group_name, var.recovery_services_vault_resource_group_name)}", "Microsoft.Storage/storageAccounts", var.storage_account_name)
      target_resource_group_id      = each.value.target_resource_group_id
      target_disk_type              = managed_disk.value.disk_type
      target_replica_disk_type      = managed_disk.value.replica_disk_type
      target_disk_encryption_set_id = managed_disk.value.target_disk_encryption_set_id
    }
  }

  dynamic "network_interface" {
    for_each = { for nic in each.value.network_interfaces : nic.network_interface_id => nic }

    content {
      source_network_interface_id        = network_interface.value.network_interface_id
      target_subnet_name                 = network_interface.value.target_subnet_name
      target_static_ip                   = network_interface.value.target_static_ip
      recovery_public_ip_address_id      = network_interface.value.recovery_public_ip_address_id
      failover_test_static_ip            = network_interface.value.failover_test_static_ip
      failover_test_subnet_name          = network_interface.value.failover_test_subnet_name
      failover_test_public_ip_address_id = network_interface.value.failover_test_public_ip_address_id
    }
  }

  timeouts {
    create = "5h30m"
    update = "2h"
    delete = "20m"
  }

  depends_on = [azurerm_site_recovery_network_mapping.network_mapping]

  lifecycle {
    ignore_changes = [
      unmanaged_disk
    ]
  }
}
