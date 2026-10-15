# AppSec Exercise - Vulnerable Web App with MongoDB

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

### Component Map

| Component | Resource | Purpose |
|---|---|---|
| `app.py` | Flask routes | `/` (index), `/login` (auth), `/api/contacts` (REST), `/contacts/create` (POST), `/contacts/delete` (POST), `/health` (debug endpoint) |
| `seed_db.py` | DB init | Creates `admin`/`admin123` app user in MongoDB `admin-app` database (run via init container, idempotent) |
| `terraform/main.tf` | Azure infra | VMs, AKS, ACR, networking, NSGs, storage |
| `terraform/variables.tf` | TF variables | VM sizes, versions, IP ranges, passwords |
| `terraform/outputs.tf` | TF outputs | Public/private IPs, connection strings, kubeconfig, storage info |
| `.github/workflows/app-deploy.yml` | CI/CD | Build → push → deploy to AKS |
| `.github/workflows/terraform-apply-destroy.yml` | CI/CD | Terraform apply/destroy with VM sizing inputs |
| `.github/workflows/mongo-nsg-temp-access.yml` | CI/CD | Temporary NSG IP whitelisting for external DB access |
| `.github/workflows/cortex-code-scan.yml` | CI/CD | Cortex code security scanner via GitHub Action (push to main) |

## Components

- **Frontend**: Flask web app (Python 3.11) in Docker container (python:3.11-slim) on AKS
- **Backend**: MongoDB 3.2.22 (vulnerable version) on Ubuntu 18.04 VM
- **Container Registry**: Azure Container Registry (ACR) with admin enabled
- **Orchestration**: AKS 1.35 with Azure CNI networking, Application Routing Add-on
- **IaC**: Terraform managing all Azure infrastructure
- **Security Model**: ClusterAdmin service account (over-privileged by design)

## Directory Structure

```
appsec-exercise/
├── app.py                       # Flask web application (routes: /, /login, /api/contacts, /contacts/*, /health)
├── Dockerfile                   # Container definition (python:3.11-slim)
├── requirements.txt             # Flask 2.3.3, pymongo 3.13.0, werkzeug 2.3.7
├── seed_db.py                   # MongoDB seed script (creates admin/admin123 app user, idempotent)
├── appsecexercise.txt           # Root-level ID file
├── templates/
│   ├── login.html               # Login page (username/password form)
│   └── dashboard.html           # Admin dashboard (contact management UI)
├── k8s/
│   ├── configmap.yaml           # K8s ConfigMap (MONGO_URI, MONGO_IP, SECRET_KEY)
│   ├── deployment.yaml          # K8s Deployment (Flask app + init-mongo container, ClusterAdmin SA)
│   ├── service.yaml             # K8s Service (ClusterIP, port 80 → 5000)
│   ├── ingress.yaml             # K8s Ingress (webapprouting class, app.cloudguardian.xyz)
│   ├── registry-secret.yaml     # ACR auth Secret (dockerconfigjson, placeholder)
│   ├── service-account.yaml     # Service Account (ClusterAdmin)
│   ├── cluster-role-binding.yaml # ClusterRoleBinding (cluster-admin role)
│   ├── secrets.yaml             # K8s Secrets (appsec-app-secrets, secret_key)
│   └── seed-script.yaml         # Seed script ConfigMap (embedded seed_db.py)
├── scripts/
│   ├── backup-mongo.sh          # MongoDB backup script (manual trigger)
│   └── download_tfstate.py      # Download Terraform state from Azure Blob Storage
├── terraform/
│   ├── main.tf                  # Main IaC config (VMs, AKS, ACR, NSGs, storage, networking)
│   ├── variables.tf             # Variables (VM sizes, versions, IP ranges, passwords)
│   ├── outputs.tf               # Outputs (IPs, credentials, kubeconfig, storage info)
│   ├── versions.tf              # Provider constraints (azurerm >= 4.0, random ~> 3.0)
│   └── scripts/
│       └── start-mongod.sh.tftpl # Template rendered by Terraform into VM custom_data (cloud-init)
└── .github/workflows/
    ├── app-deploy.yml                          # App build + deploy (manual)
    ├── terraform-apply-destroy.yml             # Terraform apply/destroy (manual)
    ├── mongo-nsg-temp-access.yml               # Temporary NSG IP whitelisting (manual)
    └── cortex-code-scan.yml                    # Cortex code security scan (push + manual)
```

## Deployment Steps

### Prerequisites

- Azure CLI (configured with valid credentials)
- Terraform 1.7+
- Docker
- kubectl
- GitHub CLI (gh) — for manual pipeline runs
- AZURE_CREDENTIALS GitHub secret — JSON service principal. See "Azure Service Principal Setup" below.

### Step 1: Deploy Infrastructure

Use the manual GitHub Actions workflow:

```bash
# Navigate to Actions tab in GitHub → "Terraform Apply/Destroy" → Run workflow
# Or manually:
cd terraform
terraform init
terraform apply
```

Workflow inputs:
- `action`: apply (or destroy to tear down)
- `location`: West US (default)
- `mongo_vm_size`: Standard_D2s_v3 (default) — MongoDB VM size (2vCPU, 8GB — B1s/B2s/B2ps_v2 unavailable in westus)
- `aks_vm_size`: Standard_D2s_v3 (default) — AKS node size (2vCPU, 8GB — B2s/B2s_v2 unavailable in westus)
- `aks_authorized_ips`: Comma-separated IPs/CIDRs to authorize on AKS API server

Terraform creates:
- Resource Group: `appsec-exercise-rg`
- MongoDB VM (Ubuntu 18.04) with private IP + static public IP (for SSH/backup access)
- Virtual Network (10.0.0.0/16) with:
  - `appsec-subnet` (10.0.1.0/24) — MongoDB VM
  - `aks-subnet` (10.0.2.0/24) — AKS cluster
- AKS Cluster (1 node, K8s 1.35) with Application Routing add-on
- Azure Container Registry (ACR) with admin enabled
- Storage Account (`appsecbackup<suffix>`) with:
  - `mongo-backups` container (public blob access — intentionally vulnerable)
  - `tfstate` container (private — for Terraform state)
- Network Security Groups:
  - AKS NSG: ports 80/443 from Cloudflare IPs, 443 from authorized IPs, health probes internal + AzureLoadBalancer
  - MongoDB NSG: SSH from any, port 27017 from AKS subnet only

### Step 2: Deploy the Application

Use the app-deploy workflow:

```bash
# Navigate to Actions → "App Build and Deploy" → Run workflow
# Inputs:
#   image_tag: Leave empty for git commit SHA (default) or specify custom tag
#   deploy_reason: Description of the deployment
```

The app-deploy workflow:
1. Downloads existing Terraform state from Azure Blob Storage
2. Runs `terraform init` + outputs to get Mongo private IP, passwords, ACR credentials
3. Authorizes the runner IP on the AKS API server (temporarily)
4. Builds and pushes Docker image to ACR
5. Runs Trivy vulnerability scan (non-blocking)
6. Applies K8s manifests with templated image/acr/mongo values
7. Creates TLS secret from Cloudflare Origin CA (if configured)
8. Waits for LoadBalancer IP and creates Cloudflare DNS record
9. Verifies deployment via port-forward
10. Restores AKS API authorized IPs and uploads TF state

### Step 3: Database Seeding

Database seeding is handled automatically by an **init container** in the K8s deployment. The `init-mongo` container:
1. Installs `pymongo` and `werkzeug`
2. Waits for MongoDB to be reachable at the `MONGO_URI`
3. Runs `seed_db.py` which creates the `admin`/`admin123` app user (idempotent — checks if user exists first)

Manual seeding (if needed):

```bash
cd terraform
MONGO_IP=$(terraform output -raw mongo_vm_private_ip)
MONGO_ADMIN_PASSWORD=$(terraform output -raw mongo_admin_password)
cd ..
MONGO_IP=$MONGO_IP MONGO_ADMIN_PASSWORD=$MONGO_ADMIN_PASSWORD python3 seed_db.py
```

Database connection uses authentication: `mongodb://admin:<password>@<private_ip>:27017/admin-app?authSource=admin`

## Usage Guide

### AKS API Server IP Restrictions

The AKS API server has **authorized IP ranges enabled** for security:

| IP | Purpose | When Active |
|---|---|---|
| `177.245.192.41/32` | Your admin access | Always |
| Runner IP | GitHub Actions deploy | Temporarily during workflow |

The `terraform-apply-destroy.yml` workflow sets `aks_authorized_ip_ranges` from the `aks_authorized_ips` input, defaulting to `["177.245.192.41/32"]`. The `app-deploy.yml` workflow temporarily adds the runner IP alongside your IP for deployments.

**Warning:** Empty `aks_authorized_ip_ranges` (`[]`) disables the feature entirely, allowing **all public IPs**. Always include at least your admin IP.

### Cloudflare DNS Record

The `app-deploy.yml` workflow creates the Cloudflare DNS record `app.cloudguardian.xyz` automatically:

| Step | Action |
|---|---|
| **Wait for LB IP** | Polls Kubernetes ingress until external IP is assigned (up to 5 min) |
| **Check existing** | Query Cloudflare API for existing `app` record (idempotent) |
| **Update/Create** | Deletes old records, creates new A record |
| **TTL** | 1 (automatic), proxied through Cloudflare |

**App URL:** `https://app.cloudguardian.xyz/login`

### TLS Configuration

Uses **Cloudflare Origin CA Certificate** for TLS:

1. Generate from Cloudflare Dashboard → SSL/TLS → Origin Certificates
2. Add to GitHub Secrets: `CF_ORIGIN_CA_CERT` and `CF_ORIGIN_CA_KEY`
3. Set Cloudflare SSL/TLS mode to "Full"
4. Workflow creates `tls-origin-cert` K8s Secret before deploying ingress

If Origin CA secrets are absent, the app deploys with HTTP-only (no TLS).

Each workflow assembles the four independent GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) into a `creds` JSON string at runtime via a dedicated shell step. The assembled JSON is passed to `azure/login@v3` as the `creds` input. This keeps each secret individually manageable in GitHub without a single `AZURE_CREDENTIALS` JSON blob, and `azure/login@v3` accepts `creds` with all four fields (`clientId`, `clientSecret`, `tenantId`, `subscriptionId`) for service-principal login. No `id-token: write` permission is required (this is service-principal auth, not OIDC federation).

### Required GitHub Secrets

| Secret | Purpose | Required |
|---|---|---|
| `AZURE_CLIENT_ID` | Azure service principal (appId / clientId) for Azure login | Yes |
| `AZURE_TENANT_ID` | Azure Active Directory tenant ID | Yes |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription GUID | Yes |
| `AZURE_CLIENT_SECRET` | Service principal password (client secret) | Yes |
| `CLOUDFLARE_ZONE_ID` | Zone ID for `cloudguardian.xyz` | Yes |
| `CLOUDFLARE_API_TOKEN` | API token with `Zone:DNS:Edit` permission | Yes |
| `CF_ORIGIN_CA_CERT` | Origin CA certificate (PEM) | No (for HTTPS) |
| `CF_ORIGIN_CA_KEY` | Origin CA private key (PEM) | No (for HTTPS) |
| `CORTEX_API_BASE_URL` | Cortex XDR API base URL for code scanning | No |
| `CORTEX_API_KEY` | Cortex XDR API key for code scanning | No |
| `CORTEX_API_KEY_ID` | Cortex XDR API key ID for code scanning | No |

### Authentication

| Username | Password |
|---|---|
| admin | admin123 |

### Azure Service Principal Setup

Each workflow passes four independent GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) to `azure/login@v3` by assembling them into a `creds` JSON string at runtime via a dedicated shell step. The assembled JSON is passed as the `creds` input, which expects all four fields (`clientId`, `clientSecret`, `tenantId`, `subscriptionId`) for service-principal login. This keeps each secret individually manageable in GitHub without a single `AZURE_CREDENTIALS` JSON blob.

**Generate the service principal and extract each value individually:**

```bash
SUB_ID=$(az account show --query id -o tsv)
az ad sp create-for-rpc --name "github-actions-sp" \
  --role "Owner" \
  --scopes /subscriptions/$SUB_ID
```

This outputs JSON like:

```json
{
  "appId": "xxxx-xxxx-xxxx-xxxx",
  "password": "your-client-secret",
  "tenant": "xxxx-xxxx-xxxx-xxxx",
  "name": "github-actions-sp"
}
```

Create four GitHub secrets from the output, using **these exact names**:

| Azure CLI output key | GitHub Secret name |
|---|---|
| `appId` | `AZURE_CLIENT_ID` |
| `password` | `AZURE_CLIENT_SECRET` |
| `tenant` | `AZURE_TENANT_ID` |
| (from `az account show`) | `AZURE_SUBSCRIPTION_ID` |

**Authentication mode used in workflows:****

Each workflow assembles four independent GitHub secrets (`AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) into a `creds` JSON string at runtime via a dedicated shell step. The assembled JSON is passed to `azure/login@v3` as the `creds` input, which expects all four fields (`clientId`, `clientSecret`, `tenantId`, `subscriptionId`) for service-principal login. This keeps each secret individually manageable in GitHub without a single `AZURE_CREDENTIALS` JSON blob. No `id-token: write` permission is required (this is service-principal auth, not OIDC federation).

**OIDC (recommended for production, no password rotation needed):**

`azure/login@v3` also supports passwordless OpenID Connect federation. This requires creating an OIDC federated credential in Azure AD and using only `client-id`, `tenant-id`, `subscription-id` inputs (no client secret). See [Microsoft's guide](https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect).


### Contact Management

Once logged in:
- **Create Contact**: Dashboard form (name, email, phone, company)
- **List Contacts**: Table below the form
- **Delete Contact**: Click "Delete" button
- **API Access**: `GET /api/contacts` returns contacts in JSON

All contacts stored in MongoDB (`contacts` collection), associated with the authenticated user.

## GitHub Actions Workflows

| Workflow | Trigger | Action | Purpose |
|---|---|---|---|
| `app-deploy.yml` | Manual (`workflow_dispatch`) | — | Build, push, deploy with git SHA tags; auto-authorizes runner IP + Cloudflare DNS |
| `terraform-apply-destroy.yml` | Manual (`workflow_dispatch`) | apply/destroy | Terraform apply/destroy with VM sizing + AKS authorized IPs |
| `mongo-nsg-temp-access.yml` | Manual (`workflow_dispatch`) | add/remove | Temporary NSG + AKS API IP whitelisting |
| `cortex-code-scan.yml` | Push to `main` + Manual | scan | Cortex code security scanner (GitHub Action) on the repository |

### Security Scanning

| Scanner | What | Output | Where |
|---|---|---|---|
| **Cortex Cloud Scan** (Action in `cortex-code-scan.yml`) | Full repository code scan (Terraform, Kubernetes, secrets, SCA); non-blocking (`soft-fail: true`) | CLI text in workflow logs + findings in Cortex XDR | Workflow logs + Cortex XDR console |
| **Cortex Cloud Scan** (Action in `app-deploy.yml`) | Container image scan (`scan-type: image`); non-blocking (`soft-fail: true`) | JSON report artifact | GitHub Actions Artifacts (`cortex-scan-results`) |

### Workflow Inputs (terraform-apply-destroy.yml)

| Input | Default | Description |
|---|---|---|
| `action` | `apply` | apply or destroy |
| `location` | `West US` | Azure region |
| `mongo_vm_size` | `Standard_D2s_v3` | MongoDB VM size (2vCPU, 8GB — B1s/B2s/B2ps_v2 unavailable in westus) |
| `aks_vm_size` | `Standard_D2s_v3` | AKS node VM size (2vCPU, 8GB — B2s/B2s_v2 unavailable in westus) |
| `aks_authorized_ips` | `""` | Comma-separated IPs/CIDRs to authorize on AKS API server |

### Terraform State Management

Terraform state files are stored in **Azure Blob Storage** in a private `tfstate` container.

| Workflow | State Download | State Upload |
|---|---|---|
| `terraform-apply-destroy.yml` | `az storage account list` + `az storage blob download` | `az storage blob upload` (apply only) |
| `app-deploy.yml` | `az storage account list` + `az storage blob download` | `az storage blob upload` |

The download uses Azure CLI with service principal auth to access the private `tfstate` container. The storage account name is discovered dynamically via `az storage account list` using the resource group filter.

The state download is handled by `scripts/download_tfstate.py`, which:
1. Accepts storage account name, container name, and resource group as arguments
2. Fetches the storage account key via `az storage account keys list`
3. Downloads `terraform.tfstate` from the private `tfstate` container
4. Uses `--auth-mode key` for blob access with the retrieved key

### Node.js Version Compatibility

All workflows use actions compatible with **Node.js 24** (GitHub's latest):

| Action | Version |
|---|---|
| `actions/checkout` | v5 |
| `hashicorp/setup-terraform` | v4 |
| `azure/login` | v3 |
| `actions/upload-artifact` | v6 |
| `actions/setup-node` | v5 |
| `docker/setup-buildx-action` | v4 |
| `azure/setup-kubectl` | v5 |
| `azure/setup-helm` | v4 |

## Security Warning

This project contains **intentionally vulnerable components** for educational/security testing purposes. It must not be deployed in production environments.

### Known Vulnerabilities

| Component | Vulnerability | Details |
|---|---|---|
| MongoDB 3.2.22 | CVE-2018-9161 | Unauthenticated RCE via MONGODB-CR authentication (mitigated: auth enabled, but 3.2.22 is still EoL/vulnerable) |
| MongoDB | Default binding | Binds to `0.0.0.0:27017` (all interfaces) |
| MongoDB | NSG open to AKS only | Port 27017 open from AKS subnet (10.0.2.0/24) via NSG; public IP exists but NSG blocks external Mongo access |
| Admin credentials | Default creds | admin/admin123 |
| Flask app | Secret key | Default value (`dev-secret-key-change-in-prod`) when SECRET_KEY env not set |
| Azure Blob | Public access | `mongo-backups` container has `container_access_type = "blob"` (anonymous read) |
| Storage TLS | Weak TLS | `min_tls_version = TLS1_2` (below 1.3) |
| ACR | Admin enabled | Admin user enabled for simplicity |
| K8s | ClusterAdmin | Service account `appsec-exercise-sa` bound to `cluster-admin` role |
| MongoDB VM | SSH open | NSG allows SSH from `*` (all IPs) on port 22 |

### Network Security Rules

**AKS NSG (`aks-app-nsg`):**

| Priority | Name | Ports | Source | Purpose |
|---|---|---|---|---|
| 100 | `Allow-Cloudflare-HTTP` | 80 | Cloudflare IPs | Web traffic (HTTP via Cloudflare) |
| 101 | `Allow-Cloudflare-HTTPS` | 443 | Cloudflare IPs | Web traffic (HTTPS via Cloudflare) |
| 102 | `Allow-AKS-API` | 443 | Authorized IP ranges | AKS API server access |
| 103 | `Allow-Internal-Health` | `*` | VirtualNetwork | Internal health probes |
| 104 | `Allow-LB-Health-Probes` | `*` | AzureLoadBalancer | Azure LB health probes |

**MongoDB NSG (`mongo-nsg`):**

| Priority | Name | Ports | Source | Purpose |
|---|---|---|---|---|
| 1000 | `SSH-Management` | 22 | `*` | SSH access to MongoDB VM (vulnerable: open to all) |
| 1010 | `Mongo-AKS-Only` | 27017 | AKS subnet (10.0.2.0/24) | MongoDB traffic from AKS only |

The default NSG behavior denies all inbound traffic not matching an allow rule.

### Terraform Variables

| Variable | Default | Description |
|---|---|---|
| `location` | `West US` | Azure region for all resources |
| `mongo_vm_size` | `Standard_D2s_v3` | MongoDB VM size (2vCPU, 8GB — B1s/B2s/B2ps_v2 unavailable in westus) |
| `aks_vm_size` | `Standard_D2s_v3` | AKS node pool VM size (2vCPU, 8GB — B2s/B2s_v2 unavailable in westus) |
| `vm_admin_username` | `azureuser` | Admin username for Mongo VM |
| `vm_admin_password` | `P@ssw0rd1234!` | Admin password for Mongo VM |
| `mongo_admin_password` | `admin123` | MongoDB admin user password |
| `mongo_version` | `3.2.22` | MongoDB version (intentionally vulnerable) |
| `aks_authorized_ip_ranges` | `["177.245.192.41/32"]` | CIDRs allowed to access AKS API server |
| `cloudflare_ip_ranges` | Cloudflare IPv4 ranges | IP ranges for NSG rules (Cloudflare proxy traffic) |

### Storage Account Configuration

The Azure Storage Account is intentionally misconfigured with public access enabled:

```hcl
resource "azurerm_storage_account" "backup_storage" {
  name                     = "appsecbackup${random_string.storage_suffix.result}"
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

resource "azurerm_storage_container" "backup_container" {
  name                  = "mongo-backups"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "blob"  # "blob" = anonymous read access (intentionally vulnerable)
}

resource "azurerm_storage_container" "tfstate_container" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.backup_storage.id
  container_access_type = "private"  # TF state stored privately
}
```

| Property | Value | Risk |
|---|---|---|
| `public_network_access_enabled` | `true` | Public network access allowed |
| `min_tls_version` | `TLS1_2` | Weak TLS protocol (below 1.3) |
| `container_access_type` (backup) | `blob` | Anonymous read access to all blobs |
| `container_access_type` (tfstate) | `private` | No anonymous access |
| `default_action` | `Allow` | No network restrictions |

### MongoDB VM Configuration

```hcl
resource "azurerm_linux_virtual_machine" "mongo_vm" {
  name                = "mongo-vm"
  size                = var.mongo_vm_size
  admin_username      = var.vm_admin_username
  admin_password      = var.vm_admin_password
  disable_password_authentication = false
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
  custom_data = base64encode(templatefile("${path.module}/scripts/start-mongod.sh.tftpl", {
    mongo_admin_password = var.mongo_admin_password
  }))
}

resource "azurerm_public_ip" "mongo_pip" {
  name                = "mongo-pip"
  location            = azurerm_resource_group.appsec_exercise.location
  resource_group_name = azurerm_resource_group.appsec_exercise.name
  allocation_method   = "Static"
  sku                 = "Standard"
}
```

MongoDB 3.2.22 is installed via cloud-init (custom_data):
- Downloads MongoDB 3.2.22 Linux x86_64 Ubuntu 16.04 binary from `https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu1604-3.2.22.tgz`
- Extracts and copies binaries to `/usr/local/bin/`
- Starts **without** `--auth`, creates admin user via localhost exception
- Restarts **with** `--auth` flag enabled
- Binds to `0.0.0.0:27017` (all interfaces; NSG restricts to AKS subnet on 27017)
- **Admin credentials**: `admin` / `var.mongo_admin_password` (default: `admin123`)
- Runs as daemon via `nohup mongod ... --fork` (survives VM reboot)
- Logs to `/var/log/mongodb/mongod.log` and `/home/azureuser/logs/mongod.out`

The `start-mongod.sh.tftpl` template is rendered by Terraform's `templatefile()` and injected into the VM's `custom_data` field. It receives `mongo_admin_password` as a template variable.

### Network Architecture

```
VNet: 10.0.0.0/16
├── Subnet: 10.0.1.0/24 (appsec-subnet)
│   └── MongoDB VM (Standard_D2s_v3)
│       ├── Private IP (dynamic)
│       ├── Public IP (Standard SKU, static)
│       └── NSG: SSH from *, Mongo 27017 only from AKS subnet (10.0.2.0/24)
├── Subnet: 10.0.2.0/24 (aks-subnet)
│   └── AKS Cluster (1 node, Standard_D2s_v3, K8s 1.35)
│       └── Application Routing Add-on (ingress via webapprouting.kubernetes.azure.com)
└── Service CIDR: 10.0.3.0/24 (DNS: 10.0.3.10)
```

### AKS Cluster Configuration

```hcl
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

  web_app_routing {
    dns_zone_ids = []  # Empty = AKS auto-creates DNS zone
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "10.0.3.0/24"
    dns_service_ip = "10.0.3.10"
  }

  api_server_access_profile {
    authorized_ip_ranges = var.aks_authorized_ip_ranges
  }
}
```

### Terraform Outputs

| Output | Description |
|---|---|
| `mongo_vm_public_ip` | Public IP of MongoDB VM |
| `mongo_vm_private_ip` | Private IP of MongoDB VM |
| `mongo_connection_string` | MongoDB connection string with credentials (sensitive) |
| `mongo_admin_password` | Password for MongoDB admin user (sensitive) |
| `acr_login_server` | Azure Container Registry login server |
| `acr_username` | ACR admin username |
| `acr_password` | ACR admin password (sensitive) |
| `aks_kube_config` | Raw kubeconfig for AKS cluster (sensitive) |
| `aks_nsg_id` | AKS Network Security Group ID |
| `aks_nsg_name` | AKS Network Security Group name |
| `storage_account_name` | Storage account name for backups and TF state |
| `storage_container_name` | Blob container for backups (`mongo-backups`) |
| `tfstate_container_name` | Blob container for TF state (`tfstate`, private) |
| `storage_primary_blob_endpoint` | Storage account blob endpoint URL |
| `storage_blob_access_key` | Storage account access key (sensitive) |

### ConfigMap Pattern (MongoDB IP Injection)

The MongoDB VM private IP is exposed dynamically via Terraform outputs and injected into the Flask app Kubernetes deployment via a ConfigMap. The `app-deploy.yml` workflow dynamically captures the private IP after Terraform apply and creates the ConfigMap:

```bash
kubectl create configmap appsec-app-config \
  --from-literal=MONGO_URI="mongodb://admin:${MONGO_ADMIN_PASSWORD}@${MONGO_IP}:27017/admin-app?authSource=admin" \
  --from-literal=MONGO_IP="${MONGO_IP}" \
  --from-literal=SECRET_KEY="appsec-secret-key" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The K8s Secrets (`appsec-app-secrets`) provide the `SECRET_KEY` via `secret_key` reference, while the ConfigMap provides `MONGO_URI` and `MONGO_IP`.

### K8s RBAC Configuration

| Resource | Name | Role |
|---|---|---|
| ServiceAccount | `appsec-exercise-sa` | App running identity |
| ClusterRoleBinding | `appsec-exercise-cluster-admin` | ClusterAdmin for service account |

The Flask app pods run with ClusterAdmin privileges — intentionally over-permissive.

### MongoDB Backup Script

The `scripts/backup-mongo.sh` script backs up MongoDB to Azure Blob Storage. It:
1. Temporarily adds the caller's IP to the MongoDB NSG rule for port 27017
2. Runs `mongodump` with authentication (`--username admin --password <pwd> --authenticationDatabase admin`)
3. Compresses the backup with `tar -czf`
4. Uploads to the `mongo-backups` blob container (publicly accessible)
5. Removes the temporary NSG rule via `trap EXIT`

### Temporary IP Access to MongoDB

A manual GitHub Actions workflow allows temporarily whitelisting a specific IP for MongoDB access on port 27017:

```bash
# Allow your IP
gh workflow run mongo-nsg-temp-access.yml -f action=add -f ip_address=123.45.67.89

# Remove your access
gh workflow run mongo-nsg-temp-access.yml -f action=remove
```

The workflow creates an NSG rule `Mongo-Allow-IP` (priority 1051) on the `mongo-nsg` security group, allowing inbound TCP 27017 from a single IP. Remove the rule when finished.

### Mitigation Recommendations (NOT applied)

- Upgrade MongoDB from 3.2.22 to a supported version (7.x)
- Restrict MongoDB VM SSH access to specific IPs (currently open from `*`)
- Restrict storage account to private endpoints only
- Set a strong `SECRET_KEY` environment variable for Flask
- Disable ACR admin credentials; use managed identity
- Upgrade `min_tls_version` to `TLS1_3`
- Downgrade K8s service account from ClusterAdmin to least-privilege role
