terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0, < 4.0"
    }
  }
}

provider "azurerm" {
  features {}
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

  # Allow Mongo (27017) from AKS cluster subnet only
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
  allocation_method   = "Dynamic"
}

# Mongo VM
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                = "mongo-vm"
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  location            = azurerm_resource_group.wiz_exercise.location
  size                = "Standard_B1s"
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password
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
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  os_disk {
    name              = "mongo-os-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  # Provision MongoDB vulnerable version
  provisioner "remote-exec" {
    inline = [
      "sleep 30",
      "wget -qO - https://www.mongodb.org/static/pgp/server-3.2.asc | sudo apt-key add -",
      "echo 'deb http://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/3.2 ubuntu' | sudo tee /etc/apt/sources.list.d/mongodb-org-3.2.list",
      "sudo apt-get update",
      "sudo apt-get install -y mongodb-org=${var.mongo_version}",
      "sudo systemctl start mongod",
      "sudo systemctl enable mongod"
    ]
  }

  connection {
    type        = "ssh"
    user        = var.vm_admin_username
    password    = var.vm_admin_password
    host        = azurerm_public_ip.mongo_pip.ip_address
    timeout     = "10m"
  }
}

# App VM NIC
# (Removed - app now runs in AKS)

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "wizacr${formatdate("DDMMYYYYhhmmss", timestamp())}"
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

  delegation {
    name = "aks_delegation"
    service_delegation {
      name = "Microsoft.ContainerService/managedClusters"
    }
  }
}

# AKS Cluster - uses same VNet as Mongo VM
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "wiz-aks-cluster"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  dns_prefix          = "wizaks"

  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = "Standard_B1s"
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.3.0/24"
    dns_service_ip = "10.0.3.10"
  }
}

# AKS ACR Role Assignment
resource "azurerm_role_assignment" "acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# Storage Account for backups (with public access - intentionally vulnerable)
resource "azurerm_storage_account" "backup_storage" {
  name                     = "wizbackup${formatdate("DDMMYYYYhhmmss", timestamp())}"
  resource_group_name      = azurerm_resource_group.wiz_exercise.name
  location                 = azurerm_resource_group.wiz_exercise.location
  account_tier             = "Standard"
  account_replication_type  = "LRS"
  account_kind             = "StorageV2"

  # Intentionally vulnerable: Allow public access to blob
  public_network_access_enabled = true
  min_tls_version                = "TLS1_0"

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
}

# Blob container with public access (vulnerable misconfiguration)
resource "azurerm_storage_container" "backup_container" {
  name                  = "mongo-backups"
  storage_account_name  = azurerm_storage_account.backup_storage.name
  container_access_type = "blob"  # "blob" = anonymous read access to blobs (vulnerable)
}