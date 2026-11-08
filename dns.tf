# Private DNS for the Azure Managed Redis private endpoint.
#
# The zone lives in the central DNS resource group (default: crm-vnet, where the
# other privatelink.* zones are). main.tf references it via
# data.azurerm_private_dns_zone.redis.
#
# NOTE: because main.tf uses a data source for the zone, the zone must exist
# before a full plan/apply. On first deployment run:
#   terraform apply -target=azurerm_virtual_network.redis -target=azurerm_subnet.redis_pe -target=azurerm_private_dns_zone.redis -target=azurerm_private_dns_zone_virtual_network_link.redis
# then run terraform apply as usual.
resource "azurerm_private_dns_zone" "redis" {
  name                = var.private_dns_zone_name
  resource_group_name = var.private_dns_zone_resource_group_name

  tags = var.tags
}

# Link the zone to vnet-redis so clients in the VNet resolve the cluster
# hostname to the private endpoint IP
resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "redis-dns-link"
  resource_group_name   = var.private_dns_zone_resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.redis.id
  registration_enabled  = false

  tags = var.tags
}
