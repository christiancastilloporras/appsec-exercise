variable "location" {
  default = "West US"
}

variable "mongo_vm_size" {
  description = "Size of the MongoDB VM"
  # Standard_D2s_v3 is not available in westus for this subscription.
  # Standard_D2s_v6 (x64, 2vCPU, 8GB) is available and meets requirements.
  default = "Standard_D2s_v6"
}

variable "aks_vm_size" {
  description = "Size of the AKS nodes (minimum: Standard_D2s_v6 - 2vCPU, 8GB RAM)"
  # Standard_D2s_v3 not available in westus for this subscription.
  # Standard_D2s_v6 (x64, 2vCPU, 8GB) is available and meets requirements.
  default = "Standard_D2s_v6"
}

variable "vm_admin_username" {
  default = "azureuser"
}

variable "vm_admin_password" {
  default = "P@ssw0rd1234!"
}

variable "mongo_admin_password" {
  description = "Admin password for MongoDB admin user (authSource: admin)"
  default     = "admin123"
}

variable "mongo_version" {
  description = "MongoDB server version. Must have a matching ubuntu2204 binary on fastdl.mongodb.org. 3.2.22 only has ubuntu1604 builds (incompatible with Ubuntu 22.04 Jammy); minimum is 5.0+. Default: 7.0.14 (ubuntu2204)."
  default     = "7.0.14"
}

variable "aks_authorized_ip_ranges" {
  type        = list(string)
  description = "List of CIDRs allowed to access AKS API server. Must include at least one IP to enable authorized IP ranges feature. Default: user's IP for initial access."
  default     = ["177.245.192.41/32"] # User's public IP - enables authorized IP ranges
}

variable "runner_ip" {
  description = "Public IP of the GitHub Actions runner, added to mongo-nsg for port 27017 access during provisioning. Empty by default; passed via -var in CI."
  default     = ""
}

variable "tfc_organization" {
  description = "TFC organization name for remote backend"
  default     = ""
}

variable "cloudflare_ip_ranges" {
  type        = list(string)
  description = "Cloudflare IPv4 ranges for NSG rules. See https://www.cloudflare.com/ips-v4/ for current values. Note: Azure NSG rules cannot mix IPv4 and IPv6 in the same rule, so only IPv4 ranges are included here. Use separate rules for IPv6 if needed."
  default = [
    # Cloudflare IPv4 ranges (from https://www.cloudflare.com/ips-v4/)
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}