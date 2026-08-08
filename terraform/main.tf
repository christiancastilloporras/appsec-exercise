# Remove old terraform block (moved to versions.tf)
provider "azurerm" {
  features {}
}

# Cloudflare provider for DNS + Origin CA cert management
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "azurerm_resource_group" "wiz_exercise" {
  name     = "wiz-exercise-rg"
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "wiz_vnet" {
  name                = "wiz-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
}

# Subnet
resource "azurerm_subnet" "wiz_subnet" {
  name                 = "wiz-subnet"
  resource_group_name  = azurerm_resource_group.wiz_exercise.name
  virtual_network_name = azurerm_virtual_network.wiz_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Security Group
resource "azurerm_network_security_group" "wiz_nsg" {
  name                = "wiz-nsg"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name

  # Allow SSH
  security_rule {
    name                       = "SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow HTTP (web app)
  security_rule {
    name                       = "HTTP"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Mongo (27017) rule removed from shared NSG
  # Mongo VM gets its own NSG that only allows AKS cluster traffic
}

# Mongo VM
# Mongo VM NIC
resource "azurerm_network_interface" "mongo_nic" {
  name                = "mongo-nic"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name

  ip_configuration {
    name                          = "mongo-ip"
    subnet_id                     = azurerm_subnet.wiz_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mongo_pip.id
  }
}

# Mongo NSG - only allows AKS cluster traffic on 27017
resource "azurerm_network_security_group" "mongo_nsg" {
  name                = "mongo-nsg"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name

  # Allow SSH from management IP (for provisioning only)
  security_rule {
    name                       = "SSH-Management"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow Mongo (27017) from AKS cluster subnet only (internal traffic)
  security_rule {
    name                       = "Mongo-AKS-Only"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = azurerm_subnet.aks_subnet.address_prefixes[0]
    destination_address_prefix = "*"
  }
}

# Associate Mongo NSG with Mongo NIC
resource "azurerm_network_interface_security_group_association" "mongo_nsg_assoc" {
  network_interface_id      = azurerm_network_interface.mongo_nic.id
  network_security_group_id = azurerm_network_security_group.mongo_nsg.id
}

# Mongo Public IP
resource "azurerm_public_ip" "mongo_pip" {
  name                = "mongo-pip"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  allocation_method   = "Static"
  # Standard SKU (Basic is deprecated, March 31, 2025)
  sku = "Standard"
}

# Mongo VM
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                            = "mongo-vm"
  resource_group_name             = azurerm_resource_group.wiz_exercise.name
  location                        = azurerm_resource_group.wiz_exercise.location
  size                            = var.mongo_vm_size
  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  # Managed Identity for the VM
  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
    azurerm_network_interface.mongo_nic.id
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  os_disk {
    name                 = "mongo-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/start-mongod.sh.tftpl", {
    # Variables can be passed here if needed
  }))
}

# MongoDB is provisioned via cloud-init (custom_data on the VM resource)
# The startup script downloads, extracts, and starts MongoDB as a daemon
# This ensures MongoDB survives VM reboots and is properly daemonized

# Wait for cloud-init to finish and MongoDB to be ready on private IP
resource "null_resource" "mongo_wait_for_ready" {
  depends_on = [
    azurerm_linux_virtual_machine.mongo_vm,
    azurerm_public_ip.mongo_pip
  ]

  connection {
    type     = "ssh"
    user     = var.vm_admin_username
    password = var.vm_admin_password
    host     = azurerm_public_ip.mongo_pip.ip_address
    timeout  = "15m"
  }

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to complete (mongod startup is via cloud-init)
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait 2>/dev/null || echo 'cloud-init status not available, continuing'",
      # Wait for MongoDB to listen on private IP (the actual address AKS uses)
      "for i in $(seq 1 60); do",
      "  if bash -c 'echo > /dev/tcp/${azurerm_network_interface.mongo_nic.private_ip_address}/27017' 2>/dev/null; then",
      "    echo '✅ MongoDB is reachable on private IP ${azurerm_network_interface.mongo_nic.private_ip_address}:27017'",
      "    exit 0",
      "  else",
      "    echo \"⏳ MongoDB not ready yet (attempt $i/60)...\"",
      "    sleep 10",
      "  fi",
      "done",
      "echo '❌ MongoDB did not become reachable on port 27017 within 600s'",
      "echo '=== mongod.out ==='",
      "cat /home/${var.vm_admin_username}/logs/mongod.out 2>/dev/null || true",
      "echo '=== mongod.log ==='",
      "cat /var/log/mongodb/mongod.log 2>/dev/null || true",
      "echo '=== processes ==='",
      "ps aux | grep mongod || true",
      "exit 1"
    ]
  }
}

# App VM NIC
# (Removed - app now runs in AKS)

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "wizacr${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  location            = azurerm_resource_group.wiz_exercise.location
  sku                 = "Basic"
  admin_enabled       = true
}

# Subnet for AKS nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.wiz_exercise.name
  virtual_network_name = azurerm_virtual_network.wiz_vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  # AKS will automatically manage the service delegation when creating the cluster
  # Do not add delegation here - it causes conflicts
  # delegation {
  #   name = "aks_delegation"
  #   service_delegation {
  #     name = "Microsoft.ContainerService/managedClusters"
  #   }
  # }
}

# AKS Cluster - uses same VNet as Mongo VM
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "wiz-aks-cluster"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  dns_prefix          = "wizaks"
  kubernetes_version  = "1.35"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = var.aks_vm_size
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Enable Application Routing add-on (replaces deprecated http_application_routing)
  web_app_routing {
    dns_zone_ids = []

  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.3.0/24"
    dns_service_ip = "10.0.3.10"
  }

  # Restrict API server access to authorized IPs only.
  # Empty list = deny all public access (secure by default).
  api_server_access_profile {
    authorized_ip_ranges = var.aks_authorized_ip_ranges
  }
}

# AKS ACR Role Assignment
# Note: The service principal must have "User Access Administrator" or "Owner" 
# role at the subscription level to create role assignments on ACR.
# If this fails with AuthorizationFailed, either grant the role or use a custom role.
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Data source to read AKS cluster details after creation
# Used to get the auto-generated Application Routing DNS zone name
data "azurerm_kubernetes_cluster" "aks" {
  name                = azurerm_kubernetes_cluster.aks.name
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  depends_on          = [azurerm_kubernetes_cluster.aks]
}

# Cloudflare DNS Record - points Cloudflare proxy to AKS internal LB
# Uses AKS-managed ingress endpoint (Application Routing add-on)
resource "cloudflare_record" "app_dns" {
  zone_id = var.cloudflare_zone_id
  name    = "app"
  type    = "CNAME"
  value   = data.azurerm_kubernetes_cluster.aks.fqdn
  proxied = true # Enables Cloudflare proxy + WAF
  ttl     = 1
}

# Cloudflare Origin CA Certificate for TLS termination at ALB
# Note: This requires a CSR to be generated first. For simplicity, the cert
# can be created manually via Cloudflare dashboard or a separate script.
# The DNS record below enables Cloudflare proxy + WAF in front of the ALB.

# AKS NSG - restrict AKS API traffic to Cloudflare IPs + AKS internal only
resource "azurerm_network_security_group" "aks_subnet_nsg" {
  name                = "aks-subnet-nsg"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name

  # Allow HTTP/HTTPS from Cloudflare IP ranges
  security_rule {
    name                       = "Allow-Cloudflare-HTTP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefixes    = local.cloudflare_cidrs_v4
    destination_port_ranges    = ["80", "443"]
    source_port_range          = "*"
    destination_address_prefix = "*"
  }

  # Allow AKS API Server from AKS subnet (internal traffic)
  security_rule {
    name                       = "Allow-AKS-API-Internal"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = azurerm_subnet.aks_subnet.address_prefixes[0]
    destination_port_range     = "443"
    source_port_range          = "*"
    destination_address_prefix = "*"
  }

  # Allow VNet peering traffic (Mongo <-> AKS)
  security_rule {
    name                       = "Allow-VNet"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }
}

# Associate NSG with AKS subnet
resource "azurerm_subnet_network_security_group_association" "aks_nsg_assoc" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_subnet_nsg.id
}

# Data source: Cloudflare IPv4 CIDRs (fetched at plan time)
data "http" "cloudflare_cidrs" {
  url = "https://www.cloudflare.com/ips-v4"
}

locals {
  cloudflare_cidrs_v4 = [for line in split("\n", trimspace(data.http.cloudflare_cidrs.response_body)) : line if line != ""]
}

# Random suffix for unique resource names (prevents recreation on every apply)
resource "random_string" "storage_suffix" {
  length  = 12
  special = false
  upper   = false
}

# Storage Account for backups (with public access - intentionally vulnerable)
resource "azurerm_storage_account" "backup_storage" {
  name                     = "wizbackup${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.wiz_exercise.name
  location                 = azurerm_resource_group.wiz_exercise.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Intentionally vulnerable: Allow public access to blob
  public_network_access_enabled = true
  min_tls_version               = "TLS1_2"

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
}

# Blob container with public access (vulnerable misconfiguration)
resource "azurerm_storage_container" "backup_container" {
  name                  = "mongo-backups"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "blob" # "blob" = anonymous read access to blobs (vulnerable)
}

# Private container for Terraform state files
resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "private"
}