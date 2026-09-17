terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.5"
    }
  }

  # Remote state (recommended): Azure Storage account with a blob container.
  # Azure Storage has supported native lease-based locking since Terraform's
  # azurerm backend existed - no DynamoDB-style bolt-on needed here.
  #
  # backend "azurerm" {
  #   resource_group_name  = "rg-tfstate"
  #   storage_account_name = "k8saailabtfstate"   # must be globally unique, lowercase, no dashes
  #   container_name       = "tfstate"
  #   key                  = "18-infrastructure-as-code/aks/terraform.tfstate"
  #   use_azuread_auth     = true                  # prefer Entra ID auth over storage account keys
  # }
}

provider "azurerm" {
  features {}
}
