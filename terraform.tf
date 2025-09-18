terraform {
  required_version = ">= 1.3"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.115, < 5.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = ">= 2.0.1, < 3.0.0"
    }
  }
}

