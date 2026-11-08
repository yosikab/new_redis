# Declare the required provider
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "azure/azapi"
      version = "~> 2.12"
    }
    time = {
      source = "hashicorp/time"
    }
  }
}



provider "azurerm" {
  features {}

}

