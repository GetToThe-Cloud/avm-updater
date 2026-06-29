# Test fixture: Terraform file with AVM module references
# Contains two res modules — one pinned version, one ~> constraint

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# --- Pinned version ---
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.2.9"

  name                = "mystorageacct001"
  resource_group_name = "my-rg"
  location            = "eastus"
}

# --- ~> constraint (loose pin) ---
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.5"

  name                = "mykeyvault001"
  resource_group_name = "my-rg"
  location            = "eastus"
}
