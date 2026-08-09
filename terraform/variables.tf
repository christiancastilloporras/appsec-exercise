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
  description = "List of CIDRs allowed to access AKS API server. Must include at least one IP to enable authorized IP ranges feature. Default: user's IP for initial access."
  default     = ["177.245.192.41/32"] # User's public IP - enables authorized IP ranges
}

variable "cloudflare_ip_ranges" {
  type        = list(string)
  description = "Cloudflare IPv4 ranges for NSG rules. See https://www.cloudflare.com/ips/ for current values. Note: Azure NSG rules cannot mix IPv4 and IPv6 in the same rule, so only IPv4 ranges are included here. Use separate rules for IPv6 if needed."
  default = [
    # Cloudflare IPv4 ranges
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "188.114.112.0/20",
    "141.101.64.0/18",
    "103.21.244.0/22",
    "172.64.0.0/13",
    "104.16.0.0/8",
  ]
}