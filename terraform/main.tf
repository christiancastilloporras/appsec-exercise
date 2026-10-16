# Remove old terraform block (moved to versions.tf)
provider "azurerm" {
  features {}
}

# Cloudflare provider for DNS + Origin CA cert management
# Cloudflare provider for DNS + Origin CA cert management

resource "azurerm_resource_group" "appsec_exercise" {
  name     = "appsec-exercise-rg"
  location = var.location
}

# Virtual Network
resource "azurerm_virtual_network" "appsec_vnet" {
  name                = "appsec-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name
}

# Subnet for MongoDB VM
resource "azurerm_subnet" "appsec_subnet" {
  name                 = "appsec-subnet"
  resource_group_name  = azurerm_resource_group.appsec_exercise.name
  virtual_network_name = azurerm_virtual_network.appsec_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Security Group
resource "azurerm_network_security_group" "appsec_nsg" {
  name                = "appsec-nsg"
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name

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
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name

  ip_configuration {
    name                          = "mongo-ip"
    subnet_id                     = azurerm_subnet.appsec_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.mongo_pip.id
  }
}

# Mongo NSG - only allows AKS cluster traffic on 27017
resource "azurerm_network_security_group" "mongo_nsg" {
  name                = "mongo-nsg"
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name

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

  # Temporarily allow Mongo (27017) from anywhere during provisioning.
  # This rule is removed after provisioning completes via a workflow
  # post-step that deletes the rule, leaving only Mongo-AKS-Only.
  security_rule {
    name                       = "Mongo-Runner-Temp"
    priority                   = 1020
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "27017"
    source_address_prefix      = "0.0.0.0/0"
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
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name
  allocation_method   = "Static"
  # Standard SKU (Basic is deprecated, March 31, 2025)
  sku = "Standard"
}

# Mongo VM
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                            = "mongo-vm"
  resource_group_name             = azurerm_resource_group.appsec_exercise.name
  location                        = azurerm_resource_group.appsec_exercise.location
  size                            = var.mongo_vm_size
  admin_username                  = var.vm_admin_username
  admin_password                  = var.vm_admin_password
  disable_password_authentication = false

  # No managed identity assigned (removed SystemAssigned)
  network_interface_ids = [
    azurerm_network_interface.mongo_nic.id
  ]

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  os_disk {
    name                 = "mongo-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  custom_data = base64encode(templatefile("${path.module}/scripts/start-mongod.sh.tftpl", {
    mongo_admin_password = var.mongo_admin_password
    mongo_version        = var.mongo_version
  }))
}

# MongoDB is provisioned via cloud-init (custom_data on the VM resource)
# The startup script downloads, extracts, and starts MongoDB as a daemon
# This ensures MongoDB survives VM reboots and is properly daemonized

# Wait for cloud-init to finish and MongoDB to be ready on port 27017
# We use a two-step approach: the 'file' provisioner uploads the rendered
# bash script to the VM, then 'remote-exec' executes it with /bin/bash.
# This avoids sh syntax issues (remote-exec inline defaults to sh on Ubuntu)
# by explicitly using bash to run the script.
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

  # Upload the wait-for-mongo.sh script with template variables rendered
  provisioner "file" {
    source      = "${path.module}/scripts/wait-for-mongo.sh"
    destination = "/tmp/wait-for-mongo.sh"
  }

  # Replace placeholders with Terraform-resolved values and execute with bash
  provisioner "remote-exec" {
    inline = [
      "sed -i 's/__MONGO_PUBLIC_IP__/${azurerm_public_ip.mongo_pip.ip_address}/g' /tmp/wait-for-mongo.sh",
      "sed -i 's/__VM_ADMIN_USERNAME__/${var.vm_admin_username}/g' /tmp/wait-for-mongo.sh",
      "chmod +x /tmp/wait-for-mongo.sh",
      "/bin/bash /tmp/wait-for-mongo.sh"
    ]
  }
}

# App VM NIC
# (Removed - app now runs in AKS)

# Azure Container Registry
# Premium SKU is required because Azure Policy enforces
# public_network_access_enabled = false, which is not supported on Basic
# SKU. Premium SKU supports both public_network_access_enabled = false
# and network_rule_set for additional security.
resource "azurerm_container_registry" "acr" {
  name                = "appsecacr${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.appsec_exercise.name
  location            = azurerm_resource_group.appsec_exercise.location
  sku                 = "Premium"
  admin_enabled       = true

  network_rule_set {
    default_action = "Allow"
    # Could restrict to VNet/AKS subnet here, but keeping Allow for simplicity
    # since the exercise focuses on MongoDB backup exposure
  }
}

# Subnet for AKS nodes
resource "azurerm_subnet" "aks_subnet" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.appsec_exercise.name
  virtual_network_name = azurerm_virtual_network.appsec_vnet.name
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

# Network Security Group for AKS cluster - only allows Cloudflare IPs
# Cloudflare publishes their IP ranges at https://www.cloudflare.com/ips/
resource "azurerm_network_security_group" "aks_nsg" {
  name                = "aks-app-nsg"
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name

  # Allow HTTP from Cloudflare only (ports 80/443 are for web traffic)
  security_rule {
    name                       = "Allow-Cloudflare-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.cloudflare_ip_ranges
    destination_address_prefix = "*"
  }

  # Allow HTTPS from Cloudflare only
  security_rule {
    name                       = "Allow-Cloudflare-HTTPS"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.cloudflare_ip_ranges
    destination_address_prefix = "*"
  }

  # Allow AKS API server (for kubectl access via API server authorized IPs)
  security_rule {
    name                       = "Allow-AKS-API"
    priority                   = 102
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.aks_authorized_ip_ranges
    destination_address_prefix = "*"
  }

  # Allow internal health probes
  security_rule {
    name                       = "Allow-Internal-Health"
    priority                   = 103
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "*"
  }

  # Allow load balancer health probes
  security_rule {
    name                       = "Allow-LB-Health-Probes"
    priority                   = 104
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

# Associate NSG with AKS subnet (required for AZurerm provider v4+)
resource "azurerm_subnet_network_security_group_association" "aks_nsg_assoc" {
  subnet_id                 = azurerm_subnet.aks_subnet.id
  network_security_group_id = azurerm_network_security_group.aks_nsg.id
}
# AKS Cluster - uses same VNet as Mongo VM
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "appsec-aks-cluster"
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name
  dns_prefix          = "appsecaks"
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
  # This creates the webapprouting.kubernetes.azure.com ingress controller
  web_app_routing {
    dns_zone_ids = []
    # The ingress class is webapprouting.kubernetes.azure.com
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
  resource_group_name = azurerm_resource_group.appsec_exercise.name
  depends_on          = [azurerm_kubernetes_cluster.aks]
}

# Remove Cloudflare-related resources
# The app is exposed directly via AKS Load Balancer + Application Routing
# No Cloudflare proxy/WAF configuration in this revert
resource "random_string" "storage_suffix" {
  length  = 12
  special = false
  upper   = false
}

# Storage Account for backups
resource "azurerm_storage_account" "backup_storage" {
  name                     = "appsecbackup${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.appsec_exercise.name
  location                 = azurerm_resource_group.appsec_exercise.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  # Azure Policy: "Storage accounts should restrict network access" (Deny)
  # requires public_network_access_enabled = false. The backup script
  # connects via the storage account key (--auth-mode key), which still
  # requires public network access being disabled — GitHub Actions runners
  # connect over the Azure public endpoint using account key authentication.
  # Only the TF state container is private; backup container uses key auth.
  public_network_access_enabled = false
  min_tls_version               = "TLS1_2"

  # Network rules: deny by default, allow Azure services, and allow
  # GitHub Actions runner IPs dynamically during TF state upload/download.
  # The ip_rules are managed dynamically via az CLI in the workflow/scripts
  # since GitHub runner IPs are not static and change frequently.
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Blob container for MongoDB backups (private access — Azure Policy blocks public)
# The exercise demonstrates the risk of leaked SAS tokens or exposed storage
# account keys, which can grant unauthorized blob read/write access.
# SAS tokens are generated at runtime (not stored in TF state).
resource "azurerm_storage_container" "backup_container" {
  name                  = "mongo-backups"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "private"
}

# Private container for Terraform state files
resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "private"
}