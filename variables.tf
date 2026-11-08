variable "location" {
  type        = string
  default     = "israelcentral"
  description = "The Azure region where the resources will be deployed."
}

variable "resource_group_name" {
  type        = string
  default     = "aks_services_rg"
  description = "The name of the resource group where the resources will be deployed."
}

variable "redis_name" {
  type        = string
  default     = "my-redis-cache"
  description = "The name of the Azure Cache for Redis instance."
}

variable "redis_sku_name" {
  type        = string
  default     = "Balanced_B5"
  description = "The SKU of the Azure Managed Redis instance, e.g. Balanced_B0, Balanced_B3, Balanced_B5, MemoryOptimized_M10, ComputeOptimized_X5."
}

variable "key_vault_name" {
  type        = string
  default     = null
  description = "The name of the Key Vault holding the customer-managed key. If null, a name is generated from the subscription ID."
}

variable "cmk_key_name" {
  type        = string
  default     = "redis-cmk"
  description = "The name of the customer-managed key in Key Vault."
}

variable "private_dns_zone_name" {
  type        = string
  default     = "privatelink.redisenterprise.cache.azure.net"
  description = "The name of the private DNS zone for Azure Managed Redis private endpoints."
}

variable "private_dns_zone_resource_group_name" {
  type        = string
  default     = "crm-vnet"
  description = "The resource group where the private DNS zone is deployed (the central DNS resource group)."
}

variable "log_analytics_workspace_name" {
  type        = string
  default     = "crm-vnet-logworspace-weste"
  description = "The name of the existing Log Analytics workspace receiving the Redis diagnostic logs."
}

variable "log_analytics_workspace_resource_group_name" {
  type        = string
  default     = "crm-vnet"
  description = "The resource group of the existing Log Analytics workspace."
}

variable "tags" {
  type        = map(string)
  default     = { environment = "dev" }
  description = "A mapping of tags to assign to the resources."
}
