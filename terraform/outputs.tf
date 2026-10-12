# ============================================================
# MongoDB Outputs
# ============================================================

output "mongo_connection_string" {
  # Public IP for external access (MongoDB Compass, mongosh, etc.)
  # Requires NSG rule allowing your IP on port 27017
  # Includes authentication credentials
  value     = "mongodb://admin:${var.mongo_admin_password}@${azurerm_public_ip.mongo_pip.ip_address}:27017/admin-app?authSource=admin"
  sensitive = true
}

output "mongo_admin_password" {
  description = "Password for MongoDB admin user"
  value       = var.mongo_admin_password
  sensitive   = true
}

output "mongo_vm_public_ip" {
  value = azurerm_public_ip.mongo_pip.ip_address
}

output "mongo_vm_private_ip" {
  # Private IP for internal AKS app connections
  value = azurerm_network_interface.mongo_nic.private_ip_address
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
  value       = "https://app.cloudguardian.xyz"
  description = "Full HTTPS URL for the application"
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

output "aks_nsg_id" {
  value = azurerm_network_security_group.aks_nsg.id
}

output "aks_nsg_name" {
  value = azurerm_network_security_group.aks_nsg.name
}
