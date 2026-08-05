variable "location" {
  default = "West US"
}

variable "mongo_vm_size" {
  description = "Size of the MongoDB VM"
  default     = "Standard_B1s"
}

variable "aks_vm_size" {
  description = "Size of the AKS nodes"
  default     = "Standard_B1s"
}

variable "vm_admin_username" {
  default = "azureuser"
}

variable "vm_admin_password" {
  default = "P@ssw0rd1234!"
}

variable "mongo_version" {
  default = "3.2.22"
}