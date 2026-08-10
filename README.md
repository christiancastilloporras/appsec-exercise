# WIZ Exercise - Vulnerable Web App with MongoDB

## Overview

Flask web application deployed on Azure Kubernetes Service (AKS), backed by a vulnerable MongoDB 3.2.22 instance running on a separate Azure VM. The project intentionally includes multiple security vulnerabilities for educational and security testing purposes.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            INTERNET                                    │
└────────┬───────────────────────────────────────────────────────────────┘
         │  DNS: app.cloudguardian.xyz (proxied through Cloudflare)
         ▼
┌──────────────────┐     Cloudflare (CDN + DNS + TLS Termination)
│  Cloudflare       │
│  (Proxy Mode:     │
│   Full/Strict)    │
└────────┬──────────┘
         │ HTTPS (Cloudflare Origin CA)
         ▼
┌──────────────────┐     Azure Load Balancer
│  Azure LB         │     Public IP
└────────┬──────────┘
         │  443 (TLS)
         ▼
┌──────────────────┐     AKS Application Routing Ingress
│  Ingress          │     (webapprouting.kubernetes.azure.com)
│  (nginx)          │
└────────┬──────────┘
         │  HTTP/HTTPS
         ▼
┌──────────────────┐     Flask App Container
│  AKS Pod          │     ├── app.py (routes)
│                    │     ├── MongoDB connection via MONGO_URI
└────────┬──────────┘
         │  TCP 27017
         ▼
┌──────────────────────────────────────────┐
│  MongoDB VM (Ubuntu 18.04 LTS)              │
│  Port: 27017 (authSource=admin)          │
│  Vulnerability: binds 0.0.0.0:27017      │
│           ↓                                 │
│  Azure Blob Storage (public access)       │
│  backups via backup-mongo.sh              │
│  (uses MongoDB 3.2.22 ubuntu1604 binary)  │
└──────────────────────────────────────────┘

AKS → pulls images → Azure Container Registry (ACR)
```

### Component Map (from graphify analysis)

| Component | Resource | Purpose |
|---|---|---|
| `app.py` | Flask routes | `/` (index), `/login` (auth), `/api/contacts` (REST), `/<username>/contacts` (CRUD) |
| `seed_db.py` | DB init | Creates `admin`/`admin123` app user in MongoDB `admin-app` database (requires MongoDB auth enabled by `start-mongod.sh`) |
| `terraform/main.tf` | Azure infra | VMs, AKS, ACR, networking, storage |
| `terraform/outputs.tf` | TF outputs | Public/private IPs, connection strings, kubeconfig |
| `.github/workflows/app-deploy.yml` | CI/CD | Build → push → deploy to AKS |
| `.github/workflows/terraform-apply-destroy.yml` | CI/CD | Terraform apply/destroy with VM sizing inputs |
| `.github/workflows/backup-cron.yml` | Daily job | MongoDB dumps to public Azure Blob Storage |
| `.github/workflows/mongo-nsg-temp-access.yml` | CI/CD | Temporary NSG IP whitelisting for external DB access |

## Components

- **Frontend**: Flask web app (Python 3.11) in Docker container on AKS
- **Backend**: MongoDB 3.2.22 (vulnerable version) on Ubuntu 18.04 VM
- **Container Registry**: Azure Container Registry (ACR) with admin enabled
- **Orchestration**: AKS 1.35 with Azure CNI networking, Application Routing Add-on
- **IaC**: Terraform managing all Azure infrastructure
- **Backups**: Daily MongoDB dumps to publicly accessible Azure Blob Storage
- **Security Model**: ClusterAdmin service account (over-privileged by design)

## Directory Structure

```
WIZ-exercise/
├── app.py              # Flask web application
├── Dockerfile          # Container definition
├── requirements.txt    # Python dependencies
├── seed_db.py          # MongoDB seed script (admin user)
├── templates/
│   ├── login.html      # Login page
│   └── dashboard.html  # Admin dashboard
├── k8s/
│   ├── configmap.yaml          # K8s ConfigMap (MONGO_URI)
│   ├── deployment.yaml         # K8s Deployment (Flask app + ClusterAdmin)
│   ├── service.yaml            # K8s Service
│   ├── ingress.yaml            # K8s Ingress
│   ├── registry-secret.yaml    # ACR auth Secret
│   ├── service-account.yaml    # Service Account (ClusterAdmin)
│   ├── secrets.yaml            # K8s Secrets
│   ├── cluster-role-binding.yaml # ClusterRoleBinding
│   └── seed-script.yaml        # Seed script ConfigMap (embedded seed_db.py)
├── scripts/
│   ├── backup-mongo.sh         # MongoDB backup script (daily cron)
│   └── download_tfstate.py     # Download Terraform state from Azure Blob Storage
├── wizexercise.txt         # Root-level ID file
├── .github/workflows/
│   ├── app-deploy.yml                # App build + deploy (manual)
│   ├── terraform-apply-destroy.yml   # Terraform apply/destroy with VM sizing
│   ├── mongo-nsg-temp-access.yml     # Temporary NSG IP whitelisting workflow
│   └── backup-cron.yml               # Daily MongoDB backup (cron)
├── README.md               # This file
└── terraform/
    ├── main.tf                     # Main IaC config (VMs, AKS, ACR)
    ├── variables.tf                # Variables (VM sizes, versions, IP ranges)
    ├── outputs.tf                  # Outputs (IPs, credentials, kubeconfig)
    ├── versions.tf                 # Provider version constraints
    └── scripts/
        ├── start-mongod.sh         # MongoDB startup script (cloud-init)
        └── start-mongod.sh.tftpl   # Template rendered by Terraform into custom_data
```

## Deployment Steps

### Prerequisites

- Azure CLI (configured with valid credentials)
- Terraform 1.0+
- Docker
- kubectl
- GitHub CLI (gh) — for manual pipeline runs
- AZURE_CREDENTIALS GitHub secret (JSON from `az ad sp create-for-rbac`)

### Step 1: Deploy Infrastructure

Use the manual GitHub Actions workflow:

```bash
# Navigate to Actions tab in GitHub → "Infrastructure Deploy" → Run workflow
# Or manually:
cd terraform
terraform init
terraform apply
```

Or use the dedicated Terraform Apply/Destroy workflow with configurable VM sizes:

```bash
# Navigate to Actions → "Terraform Apply/Destroy" → Run workflow
# Inputs:
#   action: apply (or destroy to tear down)
#   location: West US (default)
#   mongo_vm_size: Standard_B1s (default) - Mongo VM size
#   aks_vm_size: Standard_B2s (default) - AKS node size
```

Terraform creates:
- Resource Group: `wiz-exercise-rg`
- MongoDB VM (Ubuntu) with port 27017 open only to AKS subnet
- AKS Cluster (1 node, West US) with configurable VM size
- Azure Container Registry (ACR)
- Storage Account with public blob container for backups + private container for TF state
- Virtual Network with dedicated subnets (Mongo, AKS)

### Step 2: Deploy the Application

Use the app-deploy workflow (triggers full pipeline with configurable image tag):

```bash
# Navigate to Actions → \"App Build and Deploy\" → Run workflow
# Inputs:
#   image_tag: Leave empty for git commit SHA (default) or specify custom tag
#   deploy_reason: Description of the deployment
```

Or manually:

```bash
cd terraform
terraform apply

cd ..
docker build -t <acr-name>.azurecr.io/wiz-exercise:latest .
docker push <acr-name>.azurecr.io/wiz-exercise:latest
kubectl apply -f k8s/
```

### Seed the Database

```bash
cd terraform
MONGO_IP=$(terraform output -raw mongo_vm_private_ip)
cd ..
python3 seed_db.py --host $MONGO_IP
```

Creates admin user in MongoDB.

---

## Usage Guide

### AKS API Server IP Restrictions

The AKS API server has **authorized IP ranges enabled** for security:

| IP | Purpose | When Active |
|---|---|---|
| `177.245.192.41/32` | Your admin access | Always |
| Runner IP | GitHub Actions deploy | Temporarily during workflow |

**How it works:**
1. **During Terraform apply**: Your IP (`177.245.192.41/32`) is set as the authorized range
2. **During app-deploy**: Your IP + runner IP are both authorized (so GitHub Actions can deploy)
3. **After cleanup**: Your IP is restored, runner IP is removed

**Note:** Never run Terraform apply with empty `aks_authorized_ip_ranges` — Azure treats empty `[]` as "Not enabled" which allows **all public IPs** access. The workflow and variables.tf default both ensure at least your IP is always included.

1. The workflow creates a Cloudflare DNS record `app.cloudguardian.xyz` pointing to the AKS LoadBalancer IP
2. **App URL**: `http://app.cloudguardian.xyz/login`

**Note:** The Cloudflare record is created with `proxied=true`, routing traffic through Cloudflare's network. If you want direct ALB access without Cloudflare, disable proxy in the Cloudflare dashboard.

### Cloudflare DNS Record

The app-deploy workflow handles Cloudflare DNS automatically:

| Step | Action |
|---|---|
| **Wait for LB IP** | Polls Kubernetes service until external IP is assigned (up to 5 min) |
| **Check existing** | Query Cloudflare API for existing `app` record (idempotent) |
| **Update/Create** | Updates A record if exists, creates new if not |
| **TTL** | 1 (automatic, proxied through Cloudflare) |

**Required secrets:**
- `CLOUDFLARE_ZONE_ID` — Zone ID for `cloudguardian.xyz`
- `CLOUDFLARE_API_TOKEN` — API token with `Zone:DNS:Edit` + `Zone:SSL:Edit` permissions

**SSL/TLS Configuration:**

This project uses **Cloudflare Origin CA Certificate** for TLS termination between Cloudflare and the AKS LoadBalancer.

#### TLS Setup (Recommended: Pre-generated Origin CA Certificate)

This approach is simpler and more reliable than API-based certificate generation:

1. **Generate Origin CA Certificate manually**:
   - Go to **Cloudflare Dashboard → SSL/TLS → Origin Certificates → Create Certificate**
   - Choose **"Let Cloudflare generate the private key pair"**  
   - Set **Hostname(s)** to `*.cloudguardian.xyz` (wildcard) or `app.cloudguardian.xyz`
   - Select **"RSA"** certificate type
   - Click **Next** and download both files:
     - `origin.pem` (certificate)
     - `origin-key.pem` (private key)

2. **Add to GitHub Secrets**:
   - Go to GitHub Repo → Settings → Secrets and variables → Actions
   - Add new repository secrets:
     - `CF_ORIGIN_CA_CERT` → contents of `origin.pem`
     - `CF_ORIGIN_CA_KEY` → contents of `origin-key.pem`

3. **Set Cloudflare SSL/TLS Mode**:
   - Go to **Cloudflare Dashboard → SSL/TLS → Overview**
   - Set **SSL/TLS encryption** to **"Full"** mode

4. **Workflow handles TLS automatically**:
   - The `app-deploy.yml` workflow creates the `tls-origin-cert` Kubernetes Secret **before** deploying the ingress
   - The ingress manifest (`k8s/ingress.yaml`) includes a `tls:` section that references this Secret
   - If Cloudflare Origin CA secrets are not configured, the ingress is deployed without TLS (HTTP only)

#### Fallback (No TLS)
If `CF_ORIGIN_CA_CERT` is not set, the workflow deploys the app with HTTP-only access (no HTTPS).

#### Required Secrets

| Secret | Purpose | Required |
|---|---|---|
| `AZURE_CREDENTIALS` | Azure service principal for Terraform deploy | ✅ |
| `CLOUDFLARE_ZONE_ID` | Zone ID for `cloudguardian.xyz` | ✅ |
| `CLOUDFLARE_API_TOKEN` | API token with `Zone:DNS:Edit` permission | ✅ |
| `CF_ORIGIN_CA_CERT` | Pre-generated Origin CA certificate (PEM) | Optional (for HTTPS) |
| `CF_ORIGIN_CA_KEY` | Pre-generated Origin CA private key (PEM) | Optional (for HTTPS) |

### Kubeconfig Artifact

The `terraform-apply-destroy.yml` workflow saves the AKS kubeconfig as a downloadable artifact:

| Artifact Name | Contents | Retention |
|---|---|---|
| `aks-kubeconfig` | AKS admin kubeconfig file | 7 days |

Download from any workflow run: `Actions` → workflow run → `Artifacts` section → `aks-kubeconfig`

### Authentication

| Username | Password |
|----------|----------|
| admin    | admin123 |

### Contact Management

Once logged in, you can manage contacts:

- **Create Contact**: Fill out the form on the dashboard with name, email, phone, and company
- **List Contacts**: Contacts are displayed in a table below the form
- **Delete Contact**: Click the "Delete" button next to any contact
- **API Access**: `GET /api/contacts` returns contacts in JSON format

All contacts are stored in MongoDB (collection `contacts`) and associated with the authenticated user.

### Backup Access

Daily backups are stored in Azure Blob Storage:

```bash
# The blob URL is publicly accessible (intentionally misconfigured)
# Example backup file: https://<storage-account>.blob.core.windows.net/mongo-backups/mongo_<TIMESTAMP>.tar.gz
```

---

### GitHub Actions Workflows

| Workflow | Trigger | Action | Purpose |
||----------|---------|--------|---------|
|| `app-deploy.yml` | Manual (`workflow_dispatch`) | — | Build, push, deploy with git SHA tags; auto-authorizes runner IP + Cloudflare DNS |
|| `terraform-apply-destroy.yml` | Manual (`workflow_dispatch`) | apply/destroy | Terraform apply/destroy with VM sizing + AKS authorized IPs |
|| `backup-cron.yml` | Scheduled (daily 2AM UTC) + Manual | — | MongoDB backup to Azure Blob (public access) |
|| `mongo-nsg-temp-access.yml` | Manual (`workflow_dispatch`) | add/remove | Temporary NSG + AKS API IP whitelisting |

### Security Scanning

| Scanner | What | Output | Where |
||---------|------|--------|-------|
|| **Checkov** (in `terraform-apply-destroy.yml`) | Terraform IaC scan | SARIF artifact | GitHub Actions Artifacts (`checkov-results`) |
|| **Trivy** (in `app-deploy.yml`) | Container image vulnerabilities | SARIF + TXT artifact | GitHub Actions Artifacts (`trivy-scan-results`) |

Both scanners use pinned action versions to avoid Node.js 16 deprecation warnings. Results are saved as workflow artifacts for manual review in SARIF viewers. To view SARIF results:
1. Go to the workflow run → Artifacts section
2. Download the relevant artifact
3. Use a SARIF viewer such as [https://microsoft.github.io/](https://microsoft.github.io/) to analyze the SARIF file

### Workflow Inputs (terraform-apply-destroy.yml)

| Input | Default | Description |
|-------|---------|-------------|
| `action` | `apply` | apply or destroy |
| `location` | `West US` | Azure region |
| `mongo_vm_size` | `Standard_B1s` | MongoDB VM size |
| `aks_vm_size` | `Standard_B2s` | AKS node VM size (minimum required for AKS) |
| `aks_authorized_ips` | `""` | Comma-separated IPs/CIDRs to authorize on AKS API server |

### Terraform State Management

Terraform state files are stored in **Azure Blob Storage** (not GitHub Releases) in a private `tfstate` container.

|| Workflow | State Download | State Upload |
|-----------|---------------|---------------|
| `terraform-apply-destroy.yml` | `az storage account list` + `az storage blob download` | `az storage blob upload` (apply only) |
| `app-deploy.yml` | `az storage account list` + `az storage blob download` | `az storage blob upload` |
| `backup-cron.yml` | `az storage account list` + `az storage blob download` | N/A (read-only) |

The download step uses Azure CLI with service principal authentication (`--auth-mode login`) to access the private TF state container. The storage account name is discovered dynamically via `az storage account list` using the resource group filter.

The state download is handled by `scripts/download_tfstate.py`, which:
1. Accepts storage account name, container name, and resource group as arguments
2. Fetches the storage account key via `az storage account keys list`
3. Downloads `terraform.tfstate` from the private `tfstate` container
4. Uses `--auth-mode key` for blob access with the retrieved key

### Node.js Version Compatibility

All workflows use actions compatible with **Node.js 24** (GitHub's latest):

|| Action | Version |
||--------|---------|
|| `actions/checkout` | v5 |
|| `hashicorp/setup-terraform` | v4 |
|| `azure/login` | v3 |
|| `docker/setup-buildx-action` | v4 |
||| `azure/setup-kubectl` | v5 |

## Security Warning

This project contains **intentionally vulnerable components** for educational/security testing purposes. It must not be deployed in production environments.

### Known Vulnerabilities

| Component | Vulnerability | Details |
|-----------|--------------|---------|
| MongoDB 3.2.22 | CVE-2018-9161 | Unauthenticated RCE via MONGODB-CR authentication |
| MongoDB | Default binding | Binds to 0.0.0.0 (all interfaces) |
| MongoDB | Public port | Port 27017 exposed via public IP (SSH) but app connects via private IP |
| Admin credentials | Default creds | admin/admin123 |
| Flask app | Secret key | Default value (`dev-secret-key-change-in-prod`) when unset |
| Azure Blob | Public access | Container misconfigured with read access to all |
| Storage TLS | Weak TLS | `min_tls_version = TLS1_2` (still below 1.3) |
| ACR | Admin enabled | Admin user enabled for simplicity |

### Network Security Rules

| Priority | Name | Ports | Source | Purpose |
|---|---|---|---|---|
| 100 | `Allow-Cloudflare-HTTP` | 80 | Cloudflare IPs | Web traffic (HTTP via Cloudflare) |
| 101 | `Allow-Cloudflare-HTTPS` | 443 | Cloudflare IPs | Web traffic (HTTPS via Cloudflare) |
| 102 | `Allow-AKS-API` | 443 | Authorized IP ranges | AKS API server access |
| 103 | `Allow-Internal-Health` | * | VirtualNetwork | Internal health probes |
| 104 | `Allow-LB-Health-Probes` | * | AzureLoadBalancer | Azure LB health probes |

**Note:** The default NSG behavior denies all inbound traffic not matching an allow rule, providing a zero-trust posture for the AKS cluster nodes.

### Terraform Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `location` | `West US` | Azure region for all resources |
| `mongo_vm_size` | `Standard_B1s` | MongoDB VM size (1vCPU, 1GB RAM) |
| `aks_vm_size` | `Standard_B2s` | AKS node pool VM size (2vCPU, 4GB RAM - minimum for AKS) |
| `vm_admin_username` | `azureuser` | Admin username for Mongo VM |
| `vm_admin_password` | `P@ssw0rd1234!` | Admin password for Mongo VM |
| `mongo_version` | `3.2.22` | MongoDB version (intentionally vulnerable) |
| `aks_authorized_ip_ranges` | `[]` | List of CIDRs for AKS API server access (empty = block all) |
| `cloudflare_ip_ranges` | Cloudflare IPs | IP ranges for NSG rules (Cloudflare proxy traffic) |

### AKS Cluster Configuration

### Architecture (Simplified - Single Load Balancer)

```
Internet
   ↓
[AKS Application Routing (nginx controller)]
   ↓ (ClusterIP Service)
[Flask App Pod (port 5000)]
   ↓
[MongoDB 3.2.22 VM (private IP)]
```

**Components:**
| Component | Type | Managed By |
|---|---|---|
| `external-nginx` | LoadBalancer (external IP) | AKS Web App Routing addon (auto-created) |
| `wiz-exercise-ingress` | Ingress (`webapprouting` class) | Your workflow |
| `wiz-exercise-service` | ClusterIP (internal only) | Your workflow |
| `wiz-exercise-app` | Deployment/Pod | Your workflow |

**Key change:** Service changed from `LoadBalancer` → `ClusterIP`. The single external LoadBalancer is provided by AKS Application Routing addon, which routes to your ingress, which routes to your ClusterIP service.

**Before:** 2 LoadBalancers (service LB + addon nginx LB)
**Now:** 1 LoadBalancer (addon nginx LB only)

### Storage Account Configuration

The Azure Storage Account is intentionally misconfigured with public access enabled:

```hcl
resource "azurerm_storage_account" "backup_storage" {
  name                     = "wizbackup${random_string.storage_suffix.result}"
  account_tier             = "Standard"
  account_replication_type  = "LRS"
  account_kind             = "StorageV2"
  
  # Intentionally vulnerable: Allow public access to blob
  public_network_access_enabled = true
  min_tls_version                = "TLS1_2"
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "backup_container" {
  name                  = "mongo-backups"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "blob"  # Allows anonymous read access (intentionally vulnerable)
}

resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "private" # TF state stored privately
}
```

| Property | Value | Risk |
|--------|-------|------|
| `public_network_access_enabled` | `true` | Public network access allowed |
| `min_tls_version` | `TLS1_2` | Weak TLS protocol (still below 1.3) |
| `container_access_type` | `blob` | Anonymous read access to all blobs |
| `default_action` | `Allow` | No network restrictions |

### MongoDB VM Configuration

```hcl
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                = "mongo-vm"
  size                = var.mongo_vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password
  disable_password_authentication = false
  
  # Managed Identity for Azure resource access
  identity {
    type = "SystemAssigned"
  }
  
  # Public IP - intentionally exposed
  network_interface_ids = [azurerm_network_interface.mongo_nic.id]
  
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  
  os_disk {
    name              = "mongo-os-disk"
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  
  # Provisions MongoDB 3.2.22 (vulnerable version)
  # Uses binary tarball download rather than apt repo
  # MongoDB 3.2.22 does not support apt on Ubuntu 18.04+
}

resource "azurerm_public_ip" "mongo_pip" {
  name                = "mongo-pip"
  location            = azurerm_resource_group.wiz_exercise.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  allocation_method   = "Static"
  # Standard SKU (Basic is deprecated, March 31, 2025)
  sku                 = "Standard"
}
```

MongoDB is installed post-boot via cloud-init (see `main.tf`):
- Downloads MongoDB 3.2.22 Linux x86_64 Ubuntu 16.04 binary from `https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1604-3.2.22.tgz`
- Extracts and copies binaries to `/usr/local/bin/`
- Binds to `0.0.0.0:27017` (all interfaces, port 27017 restricted to AKS subnet via NSG)
- **Authentication enabled**: MongoDB starts without `--auth`, creates admin user via localhost exception, then restarts with `--auth` flag
- **Admin credentials**: `admin` / value of `var.mongo_admin_password` (default: `admin123`)
- Starts via cloud-init (`custom_data`) — robust startup independent of Terraform session
- Runs as daemon with `nohup mongod ... --fork` (survives VM reboot and session disconnect)
- Includes startup validation: retries TCP check on 27017 for 60s, exits with error on failure
- Logs to `/var/log/mongodb/mongod.log` and `/home/azureuser/logs/mongod.out`
- Provisioning script: `terraform/scripts/start-mongod.sh` (template: `start-mongod.sh.tftpl`)

The `start-mongod.sh` script is written as a `.tftpl` template file and rendered by Terraform's `templatefile()` function into the VM's `custom_data` field. This passes the script to cloud-init for execution on first boot. The `.tftpl` file receives `mongo_admin_password` from the `var.mongo_admin_password` Terraform variable, injected into the `mongo admin --eval` command that creates the MongoDB admin user.

### Temporary IP Access to MongoDB

A manual GitHub Actions workflow allows temporarily whitelisting a specific IP address for MongoDB access via port 27017 from the internet:

```bash
# Allow your IP
gh workflow run mongo-nsg-temp-access.yml -f action=add -f ip_address=123.45.67.89

# Remove your access
gh workflow run mongo-nsg-temp-access.yml -f action=remove
```

The workflow creates an NSG rule `Mongo-Allow-IP` (priority 1051) on the `mongo-nsg` security group, allowing inbound TCP 27017 from a single IP address. Remove the rule when finished to restore the restricted security posture.

### Database Seeding (Idempotent)

The `init-mongo` init container in the Flask deployment runs `seed_db.py` on every pod restart. The script is **idempotent** — it checks if the admin user exists before inserting. The `seed_db.py` script now reads `MONGO_ADMIN_PASSWORD` from the ConfigMap and constructs an authenticated connection string using `authSource=admin`.

```python
MONGO_URI = os.environ.get('MONGO_URI', f'mongodb://admin:{MONGO_ADMIN_PASSWORD}@{MONGO_IP}:27017/admin-app?authSource=admin')
client = MongoClient(MONGO_URI)
```

This means:
- **Fresh DB**: MongoDB admin user created by `start-mongod.sh` (cloud-init), app admin user created by `seed_db.py`
- **Existing DB**: script logs "Admin user already exists" and exits without modifying data
- **Container restart**: no data loss, admin user preserved
- **Authentication required**: both MongoDB admin and app admin users must exist for connections

### Backup Script

The daily backup script (`scripts/backup-mongo.sh`) now includes **authentication** and **temporary NSG access** for the GitHub Actions Runner:

1. **NSG temp access**: Since the Runner is outside the Azure VNet and MongoDB NSG only allows AKS subnet on port 27017, the script dynamically adds the Runner's public IP to a temporary NSG rule via `az network nsg rule create`
2. **Authenticated mongodump**: Uses `--username admin --password $MONGO_ADMIN_PASSWORD --authenticationDatabase admin`
3. Creates a timestamped backup directory and compresses it with `tar -czf`
4. Uploads the `.tar.gz` archive to Azure Blob Storage (publicly accessible container)
5. Cleans up local temporary files
6. **NSG cleanup**: Uses `trap EXIT` to ensure the temporary NSG rule is always removed, even if the backup fails

```bash
#!/bin/bash
set -e

MONGO_IP=${MONGO_IP:-"localhost"}
STORAGE_ACCOUNT=${STORAGE_ACCOUNT:-""}
STORAGE_KEY=${STORAGE_KEY:-""}
CONTAINER_NAME=${CONTAINER_NAME:-"mongo-backups"}
MONGO_ADMIN_PASSWORD=${MONGO_ADMIN_PASSWORD:-""}
RESOURCE_GROUP=${RESOURCE_GROUP:-"wiz-exercise-rg"}
NSG_NAME=${NSG_NAME:-"mongo-nsg"}
RUNNER_IP=$(curl -s https://api.ipify.org)

# Add temporary NSG rule for Runner IP → MongoDB (27017)
NSG_RULE_NAME="mongo_runner_$(echo $RUNNER_IP | tr '.' '_')"
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
  --name "$NSG_RULE_NAME" --priority 1055 --direction Inbound --access Allow \
  --protocol Tcp --source-address-prefix "$RUNNER_IP/32" \
  --destination-port-ranges 27017

# Cleanup function - always remove NSG rule
cleanup_nsg() {
  az network nsg rule delete \
    --resource-group "$RESOURCE_GROUP" --nsg-name "$NSG_NAME" \
    --name "$NSG_RULE_NAME" 2>/dev/null || true
}
trap cleanup_nsg EXIT

# Dump MongoDB data with authentication
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/mongo_backup_${TIMESTAMP}"
mkdir -p $BACKUP_DIR

mongodump --host $MONGO_IP --port 27017 \
  --username admin --password "$MONGO_ADMIN_PASSWORD" \
  --authenticationDatabase admin \
  -o $BACKUP_DIR

# Compress and upload
BACKUP_FILE="${BACKUP_DIR}.tar.gz"
tar -czf $BACKUP_FILE -C /tmp $(basename $BACKUP_DIR)

az storage blob upload \
  --account-name $STORAGE_ACCOUNT --account-key $STORAGE_KEY \
  --container-name $CONTAINER_NAME --name "mongo_${TIMESTAMP}.tar.gz" \
  --file $BACKUP_FILE --auth-mode key

# Cleanup
rm -rf $BACKUP_DIR $BACKUP_FILE
```
```

### AKS Cluster Configuration

```hcl
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "wiz-aks-cluster"
  location            = var.location
  resource_group_name = azurerm_resource_group.wiz_exercise.name
  dns_prefix          = "wizaks"
  kubernetes_version  = "1.35"
  
  default_node_pool {
    name       = "default"
    node_count = 1
    vm_size    = var.aks_vm_size
    vnet_subnet_id = azurerm_subnet.aks_subnet.id
  }
  
  identity {
    type = "SystemAssigned"
  }
  
  oidc_issuer_enabled       = true
  workload_identity_enabled   = true
  
  # Enable Application Routing Add-on (replaces deprecated HTTP App Routing)
  web_app_routing {
    dns_zone_ids = []  # Empty = AKS auto-creates DNS zone
  }
  
  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.3.0/24"
    dns_service_ip = "10.0.3.10"
  }
}
```
### Terraform Outputs

| Output | Description |
|--------|-------------|
| `mongo_vm_public_ip` | Public IP of MongoDB VM |
| `mongo_connection_string` | MongoDB connection string (`mongodb://admin:<password>@<IP>:27017/admin-app?authSource=admin`) |
| `mongo_admin_password` | Password for MongoDB admin user (sensitive) |
| `mongo_vm_private_ip` | Private IP of MongoDB VM |
| `mongo_vm_identity_principal_id` | Managed Identity principal ID for Mongo VM |
| `aks_ingress_endpoint` | Ingress URL (`https://<fqdn>`) for the Flask app |
| `aks_ingress_fqdn` | FQDN for the ingress - stable for cluster lifetime |
| `app_fqdn` | Cloudflare-proxied HTTPS URL (`https://app.wiz-exercise.cloudguardian.xyz`) |
| `app_cloudflare_hostname` | Cloudflare-proxied hostname for the app |
| `acr_login_server` | Azure Container Registry login server |
| `acr_username` | ACR admin username (if enabled) |
| `acr_password` | ACR admin password (if enabled) |
| `aks_kube_config` | Raw kubeconfig for AKS cluster access |
| `aks_cluster_name` | AKS cluster name |
| `storage_account_name` | Storage account name for backups and TF state |
| `storage_container_name` | Blob container name for backups (`mongo-backups`) |
| `storage_primary_blob_endpoint` | Storage account blob endpoint URL |
| `storage_blob_access_key` | Storage access key |
| `tfstate_container_name` | Blob container name for TF state (`tfstate`, private) |
| `tfstate_storage_url` | Full URL for TF state storage |

### ConfigMap Pattern (MongoDB IP Injection)

The MongoDB VM private IP is exposed dynamically via Terraform outputs and injected into the Flask app Kubernetes deployment via a ConfigMap:

```yaml
# k8s/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: wiz-app-config
data:
  MONGO_URI: "mongodb://<mongo_vm_private_ip>:27017/admin-app"
  SECRET_KEY: "wiz-secret-key"
```

The `app-deploy.yml` workflow dynamically captures the private IP after Terraform apply:
```bash
kubectl create configmap wiz-app-config \
  --from-literal=MONGO_URI="mongodb://${MONGO_IP}:27017/admin-app" \
  --from-literal=SECRET_KEY="wiz-secret-key" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Network Architecture

```
VNet: 10.0.0.0/16
├── Subnet: 10.0.1.0/24 (wiz-subnet)
│   └── MongoDB VM (Standard_B1s)
│       ├── Public IP (Standard SKU, static)
│       └── NSG: SSH from *, Mongo 27017 only from AKS subnet (10.0.2.0/24)
├── Subnet: 10.0.2.0/24 (aks-subnet)
│   └── AKS Cluster (1 node, Standard_B2s, K8s 1.35)
│       └── Application Routing Add-on (ingress via webapprouting.kubernetes.azure.com)
└── Service CIDR: 10.0.3.0/24
```

### K8s RBAC Configuration

| Resource | Name | Role |
|----------|------|------|
| ServiceAccount | `wiz-exercise-sa` | App running identity |
| ClusterRoleBinding | `wiz-exercise-cluster-admin` | ClusterAdmin for service account |

The Flask app pods run with ClusterAdmin privileges through the service account, which is an intentionally over-permissive configuration.

### Mitigation Recommendations (NOT applied)

- Use MongoDB 7.x instead of 3.2.22
- Enable authentication and authorization
- Restrict SSH access to VPN/bastion only
- Set a strong `SECRET_KEY` environment variable
- Disable ACR admin credentials
- Use TLS 1.2+ for all connections
- Restrict storage account to private endpoints