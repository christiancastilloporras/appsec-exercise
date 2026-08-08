variable "location" {
  default = "West US"
}

variable "mongo_vm_size" {
  description = "Size of the MongoDB VM"
  default     = "Standard_B1s"
}

variable "aks_vm_size" {
  description = "Size of the AKS nodes (minimum: Standard_B2s - 2vCPU, 4GB RAM)"
  default     = "Standard_B2s"
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

variable "aks_authorized_ip_ranges" {
  type        = list(string)
  description = "List of CIDRs allowed to access AKS API server. Defaults to empty list = deny all public access."
  default     = []
}
