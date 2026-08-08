output "mongo_connection_string" {
  # Public IP for external access (MongoDB Compass, mongosh, etc.)
  # Requires NSG rule allowing your IP on port 27017
  value = "mongodb://${azurerm_public_ip.mongo_pip.ip_address}:27017/admin-app"
}

output "mongo_vm_public_ip" {
  value = azurerm_public_ip.mongo_pip.ip_address
}

output "mongo_vm_private_ip" {
  # Private IP for internal AKS app connections
  value = azurerm_network_interface.mongo_nic.private_ip_address
}

output "mongo_vm_identity_principal_id" {
  value = azurerm_linux_virtual_machine.mongo_vm.identity[0].principal_id
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_username" {
  value = azurerm_container_registry.acr.admin_username
}

output "acr_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "aks_kube_config" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}

output "aks_ingress_endpoint" {
  value = "https://${azurerm_kubernetes_cluster.aks.fqdn}"
}

# Domain from AKS Application Routing add-on
# The domain is auto-generated and stable for the cluster's lifetime
output "aks_ingress_fqdn" {
  value       = data.azurerm_kubernetes_cluster.aks.http_application_routing_zone_name
  description = "FQDN for the ingress - stable for cluster lifetime"
}

# Cloudflare DNS record for public HTTPS access
output "app_fqdn" {
  value       = "https://${cloudflare_record.app_dns.hostname}"
  description = "Public HTTPS URL for the Flask app via Cloudflare proxy"
}

output "app_cloudflare_hostname" {
  value       = cloudflare_record.app_dns.hostname
  description = "Cloudflare-proxied hostname for the app"
}

output "storage_account_name" {
  value = azurerm_storage_account.backup_storage.name
}

output "storage_container_name" {
  value = azurerm_storage_container.backup_container.name
}

output "storage_primary_blob_endpoint" {
  value = azurerm_storage_account.backup_storage.primary_blob_endpoint
}

output "storage_blob_access_key" {
  value     = azurerm_storage_account.backup_storage.primary_access_key
  sensitive = true
}

output "backup_storage_url" {
  value = "${azurerm_storage_account.backup_storage.primary_blob_endpoint}${azurerm_storage_container.backup_container.name}"
}

output "tfstate_container_name" {
  value = azurerm_storage_container.tfstate_container.name
}

output "tfstate_storage_url" {
  value = "${azurerm_storage_account.backup_storage.primary_blob_endpoint}${azurerm_storage_container.tfstate_container.name}"
}