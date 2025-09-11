# Location Configuration
variable "source_location" {
  type        = string
  description = "The source Azure region where the VM is located."
}

variable "target_location" {
  type        = string
  description = "The Azure Region for the target resources."
}

# Vault Configuration
variable "recovery_services_vault_creation_enabled" {
  type        = bool
  default     = false
  description = "A boolean flag to determine whether to deploy the Azure Recovery Services Vault or not."
  nullable    = false
}

variable "recovery_services_vault_resource_group_name" {
  type        = string
  description = "The name of the resource group where the target vault exists."
}

variable "recovery_services_vault_name" {
  type        = string
  description = "Name of the Recovery Services Vault to be created, if not using an existing one."

  validation {
    condition     = var.recovery_services_vault_creation_enabled == false || (var.recovery_services_vault_creation_enabled == true && length(var.recovery_services_vault_name) >= 3 && length(var.recovery_services_vault_name) <= 50)
    error_message = "When recovery_services_vault_creation_enabled is true, recovery_services_vault_name must be between 3 and 50 characters."
  }
}

variable "azurerm_site_recovery_fabric_name" {
  description = "Name for the fabric to ensure uniqueness."
  type = optional(object({
    source = string
    target = string
  }))
  default = null

  validation {
    condition     = var.azurerm_site_recovery_fabric_name == null || (var.azurerm_site_recovery_fabric_name != null && length(var.azurerm_site_recovery_fabric_name.source) >= 3 && length(var.azurerm_site_recovery_fabric_name.source) <= 50 && length(var.azurerm_site_recovery_fabric_name.target) >= 3 && length(var.azurerm_site_recovery_fabric_name.target) <= 50)
    error_message = "When azurerm_site_recovery_fabric_name is provided, both source and target names must be between 3 and 50 characters."
  }
}

variable "azurerm_site_recovery_protection_container" {
  description = "Name for the fabric to ensure uniqueness."
  type = optional(object({
    source = string
    target = string
  }))
  default = {
    source = "primary-protection-container"
    target = "secondary-protection-container"
  }

  validation {
    condition     = var.azurerm_site_recovery_protection_container == null || (var.azurerm_site_recovery_protection_container != null && length(var.azurerm_site_recovery_protection_container.source) >= 3 && length(var.azurerm_site_recovery_protection_container.source) <= 50 && length(var.azurerm_site_recovery_protection_container.target) >= 3 && length(var.azurerm_site_recovery_protection_container.target) <= 50)
    error_message = "When azurerm_site_recovery_protection_container is provided, both source and target names must be between 3 and 50 characters."
  }
}

# Recovery Policy Configuration
variable "virtual_machine_replication_policies" {
  description = "Virtual machine replication policies"
  type = list(object({
    name                                               = string
    recovery_point_retention_in_days                   = optional(number, 1)
    application_consistent_snapshot_frequency_in_hours = optional(number, 4)
  }))
  default = [{
    name = "24-hour-retention-policy"
  }]

  validation {
    condition     = length(var.virtual_machine_replication_policies) > 0 && alltrue([for policy in var.virtual_machine_replication_policies : length(policy.name) >= 3 && length(policy.name) <= 50 && (policy.recovery_point_retention_in_days == null || (policy.recovery_point_retention_in_days != null && policy.recovery_point_retention_in_days >= 1 && policy.recovery_point_retention_in_days <= 720)) && (policy.application_consistent_snapshot_frequency_in_hours == null || (policy.application_consistent_snapshot_frequency_in_hours != null && policy.application_consistent_snapshot_frequency_in_hours >= 0 && policy.application_consistent_snapshot_frequency_in_hours <= 24))])
    error_message = "Each replication policy must have a name between 3 and 50 characters. If provided, recovery_point_retention_in_days must be between 1 and 720, and application_consistent_snapshot_frequency_in_hours must be between 0 and 24."
  }
}

# Replicated VMs Configuration
variable "replicated_virtual_machines" {
  description = "A map of virtual machines to replicate, with their corresponding configuration."
  type = map(object({
    virtual_machine_resource_id = string
    replication_policy_name     = string
    target_resource_group_id    = string
    source_network_id           = string
    target_network_id           = string
    managed_disks = list(object({
      disk_id                       = string
      disk_type                     = string
      replica_disk_type             = string
      target_disk_encryption_set_id = optional(string)
    }))
    network_interfaces = list(object({
      network_interface_id               = string
      target_subnet_name                 = string
      target_static_ip                   = optional(string)
      recovery_public_ip_address_id      = optional(string)
      failover_test_static_ip            = optional(string)
      failover_test_subnet_name          = optional(string)
      failover_test_public_ip_address_id = optional(string)
    }))
    capacity_reservation_creation_enabled     = optional(bool)
    capacity_reservation_sku                  = optional(string)
    capacity_reservation_group_name           = optional(string)
    target_availability_set_id                = optional(string)
    target_zone                               = optional(string)
    target_edge_zone                          = optional(string)
    target_proximity_placement_group_id       = optional(string)
    target_boot_diagnostic_storage_account_id = optional(string)
    target_virtual_machine_scale_set_id       = optional(string)
    test_network_id                           = optional(string)
    multi_vm_group_name                       = optional(string)
  }))
}

# Capacity Reservation Group Configuration
variable "capacity_reservation_group_creation_enabled" {
  description = "Defines whether capacity reservation group should be created."
  type        = bool
  default     = false
}

variable "existing_capacity_reservation_group_id" {
  description = "The ID of an existing capacity reservation group to use. Leave empty if creating a new one."
  type        = string
  default     = ""
}

variable "capacity_reservation_group_name" {
  description = "The name for a new capacity reservation group common for all replicated VMs."
  type        = string
  default     = ""

  validation {
    condition     = var.capacity_reservation_group_creation_enabled == false || (var.capacity_reservation_group_creation_enabled == true && length(var.capacity_reservation_group_name) >= 3 && length(var.capacity_reservation_group_name) <= 50)
    error_message = "When capacity_reservation_group_creation_enabled is true, capacity_reservation_group_name must be between 3 and 50 characters."
  }
}

# Site Mobility Extension Automatic Update Configuration
variable "automatic_update" {
  description = "Enable or disable automatic update of site mobility extension"
  type        = bool
  default     = true
}

variable "automation_account_id" {
  description = "automation account id"
  type        = string
  default     = null

  validation {
    condition     = var.automatic_update == false || (var.automatic_update == true && var.automation_account_id != null && var.automation_account_id != "")
    error_message = "When automatic_update is set to true, automation_account_id must be provided and not be empty."
  }
}

# Staging Storage Account Configuration
variable "storage_account_creation_enabled" {
  description = "Defines whether a storage account should be created."
  type        = bool
  default     = false
}

variable "storage_account_name" {
  description = "The name of the storage account to use for staging."
  type        = string

  validation {
    condition     = var.storage_account_creation_enabled == false || (var.storage_account_creation_enabled == true && length(var.storage_account_name) >= 3 && length(var.storage_account_name) <= 24 && can(regex("^[a-z0-9]+$", var.storage_account_name)))
    error_message = "When storage_account_creation_enabled is true, storage_account_name must be between 3 and 24 characters and contain only lowercase letters and numbers."
  }
}

variable "storage_account_resource_group_name" {
  description = "The name of the resource group containing the storage account. Optional, if blank uses the recovery services vault resource group."
  type        = string
  default     = null
}

variable "staging_replication_type" {
  description = "The replication type for the staging storage account."
  type        = string
  default     = "LRS"
}

# Management
variable "enable_telemetry" {
  description = "Enable telemetry for the module."
  type        = bool
  default     = false
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to apply to all resources."
  default     = {}
}
