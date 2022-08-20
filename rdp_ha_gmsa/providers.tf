terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.00"
    }
    azapi = {
      source = "azure/azapi"
    }
  }

  backend "azurerm" {
    resource_group_name  = "prod-infra-uswest2-tfstate"
    storage_account_name = "produswest2tfstate1111"
    container_name       = "labtfstate"
    key                  = "rdslab-ae.tfstate"
    #use_azuread_auth     = true
    #subscription_id      = "77762a62-5480-4552-80c3-f87e20caa9cd"
    #tenant_id            = "72f988bf-86f1-41af-91ab-2d7cd011db47"
  }
}

provider "azapi" {
}

provider "azuread" {
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}