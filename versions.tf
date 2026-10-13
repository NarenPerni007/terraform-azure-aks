terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Uncomment and fill in for team use (remote state):
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-state"
  #   storage_account_name = "sttfstate00000"
  #   container_name       = "tfstate"
  #   key                  = "aks.terraform.tfstate"
  # }
}

provider "azurerm" {
  features {
    resource_group {
      # Keeps `terraform destroy` from failing on the AKS-managed
      # node resource group, which AKS deletes itself.
      prevent_deletion_if_contains_resources = false
    }
  }
}
