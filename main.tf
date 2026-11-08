resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

data "azurerm_client_config" "current" {}

# Azure Managed Redis (Redis Enterprise) - Azure Verified Module
# Registry: https://registry.terraform.io/modules/Azure/avm-res-cache-redisenterprise/azurerm/latest
# GitHub:   https://github.com/Azure/terraform-azurerm-avm-res-cache-redisenterprise
#
# This module supports customer-managed key (CMK) encryption natively via the
# customer_managed_key_encryption input.
module "redis" {
  source  = "Azure/avm-res-cache-redisenterprise/azurerm"
  version = "~> 0.2"

  name      = var.redis_name
  location  = var.location
  parent_id = azurerm_resource_group.this.id

  sku_name            = var.redis_sku_name
  clustering_policy   = "OSSCluster"
  eviction_policy     = "VolatileLRU"
  minimum_tls_version = "1.2"
  high_availability   = "Enabled"
  # zones must not be specified: for Balanced_B5 zone redundancy is enabled
  # automatically in regions with availability zones (like israelcentral)

  # User-assigned identity used to access the CMK in Key Vault
  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.redis_cmk.id]
  }

  # Customer-managed key encryption at rest
  # NOTE: key_encryption_key_url must be a fully versioned key URL (API requirement)
  customer_managed_key_encryption = {
    key_encryption_key_url             = module.key_vault.keys["cmk"].id
    identity_type                      = "userAssignedIdentity"
    user_assigned_identity_resource_id = azurerm_user_assigned_identity.redis_cmk.id
  }

  tags = var.tags

  depends_on = [module.key_vault]

  # Private endpoint for the Redis cluster.
  #
  # REMARK - resources required for the private endpoint (all created below):
  #   1. Subnet - azurerm_subnet.redis_pe (10.0.1.0/24 in vnet-redis) hosts the
  #      private endpoint NIC.
  #   2. Private DNS zone - existing zone referenced by
  #      data.azurerm_private_dns_zone.redis
  #      (privatelink.redisenterprise.cache.azure.net), linked to the VNet; the
  #      module's DNS zone group registers the endpoint A-record automatically.
  #   3. Static private IP - local.redis_private_ip (10.0.1.4) from local.tf;
  #      remove the ip_configurations block to use a dynamic IP instead.
  private_endpoints = {
    pe1 = {
      subnet_resource_id            = azurerm_subnet.redis_pe.id
      private_dns_zone_resource_ids = [data.azurerm_private_dns_zone.redis.id]
      ip_configurations = {
        ip1 = {
          name               = "redis-ip"
          private_ip_address = local.redis_private_ip
        }
      }
    }
  }
}

# Network for the Redis private endpoint:
#   - VNet with a dedicated subnet for the private endpoint NIC
#   - The private DNS zone is managed in dns.tf and referenced below via
#     data.azurerm_private_dns_zone.redis; the module's DNS zone group registers
#     the endpoint A-record so VNet clients resolve the hostname to the private IP
resource "azurerm_virtual_network" "redis" {
  name                = "vnet-redis"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = ["10.0.0.0/16"]

  tags = var.tags
}

resource "azurerm_subnet" "redis_pe" {
  name                 = "snet-redis-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.redis.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Private DNS zone for Managed Redis - created in dns.tf, referenced here
data "azurerm_private_dns_zone" "redis" {
  name                = var.private_dns_zone_name
  resource_group_name = var.private_dns_zone_resource_group_name
}

# Existing Log Analytics workspace receiving the Redis logs
data "azurerm_log_analytics_workspace" "redis" {
  name                = var.log_analytics_workspace_name
  resource_group_name = var.log_analytics_workspace_resource_group_name
}

# Diagnostic setting for Managed Redis.
# NOTE: the avm-res-cache-redisenterprise module (v0.2.0) has no
# diagnostic_settings input, so it is configured here.
# The ConnectionEvents log (auditing) only exists on the database resource;
# the cluster resource exposes metrics only, which are not collected.
resource "azurerm_monitor_diagnostic_setting" "redis_database" {
  name                       = "diag-${var.redis_name}-db"
  target_resource_id         = module.redis.database_id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.redis.id

  enabled_log {
    category = "ConnectionEvents"
  }
}

# Key Vault logs -> Log Analytics (all available log categories)
resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-keyvault-audit"
  target_resource_id         = module.key_vault.resource_id
  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.redis.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }
}

# User-assigned managed identity used by Redis to access the CMK in Key Vault
resource "azurerm_user_assigned_identity" "redis_cmk" {
  name                = "id-${var.redis_name}-cmk"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name

  tags = var.tags
}

# Key Vault holding the customer-managed key - Azure Verified Module
# Registry: https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm/latest
module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "~> 0.12"

  name                = coalesce(var.key_vault_name, "kv-redis-cmk-${substr(data.azurerm_client_config.current.subscription_id, 0, 8)}")
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                 = "standard"
  purge_protection_enabled = true # required for CMK
  network_acls             = null # no firewall; restrict via private_endpoints if needed

  # RBAC assignments on the vault data plane
  role_assignments = {
    # Terraform deployment principal - manages keys
    deployer = {
      role_definition_id_or_name = "Key Vault Crypto Officer"
      principal_id               = data.azurerm_client_config.current.object_id
    }
    # Redis user-assigned identity - uses the key for encryption at rest
    redis_cmk = {
      role_definition_id_or_name = "Key Vault Crypto Service Encryption User"
      principal_id               = azurerm_user_assigned_identity.redis_cmk.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  keys = {
    cmk = {
      name     = var.cmk_key_name
      key_type = "RSA"
      key_size = 2048
      key_opts = ["unwrapKey", "wrapKey"]
    }
  }

  tags = var.tags
}

