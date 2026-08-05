# WIZ Exercise - Vulnerable Web App with MongoDB

## Architecture

Flask web app deployed on **AKS** (Azure Kubernetes Service), backed by **MongoDB 3.2.22** in a VM.
Container image stored in **Azure Container Registry (ACR)**.

```
Internet
   |
[AKS Ingress] --> [Flask App (Docker)] --> [MongoDB 3.2.22 VM]
   |                                    (vulnerable)
[Azure Load Balancer]
   |
[Azure Container Registry]
   |
[Docker Image: wiz-exercise]
```

## Components

- **Frontend**: Flask web app (Docker container) with admin login
- **Backend**: MongoDB 3.2.22 (vulnerable version) on Azure VM
- **Container Registry**: Azure Container Registry (ACR)
- **Orchestration**: AKS cluster with NGINX Ingress
- **IaC**: Terraform for all Azure infrastructure

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
│   ├── configmap.yaml      # K8s ConfigMap (MONGO_URI)
│   ├── deployment.yaml     # K8s Deployment (Flask app + ClusterAdmin)
│   ├── service.yaml        # K8s Service
│   ├── ingress.yaml        # K8s Ingress
│   ├── registry-secret.yaml # ACR auth Secret
│   ├── service-account.yaml # Service Account (ClusterAdmin)
│   ├── secrets.yaml        # K8s Secrets
│   └── cluster-role-binding.yaml # ClusterRoleBinding
├── scripts/
│   └── backup-mongo.sh     # MongoDB backup script
├── wizexercise.txt         # Root-level ID file
├── .github/workflows/
│   ├── deploy.yml          # Infrastructure deploy (manual)
│   ├── app-deploy.yml      # App build + deploy (manual)
│   └── backup-cron.yml     # Daily MongoDB backup (cron)
├── README.md               # This file
└── terraform/
    ├── main.tf         # Main IaC config (VMs, AKS, ACR)
    ├── variables.tf    # Variables
    └── outputs.tf      # Outputs (IPs, credentials)
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

Terraform creates:
- Resource Group: `wiz-exercise-rg`
- MongoDB VM (Ubuntu) with port 27017 open only to AKS subnet
- AKS Cluster (3 nodes, West Europe)
- Azure Container Registry (ACR)
- Storage Account with public blob container for backups
- Virtual Network with dedicated subnets (Mongo, AKS)

## Security Warning

This setup intentionally deploys a vulnerable MongoDB instance.
DO NOT deploy to production. For educational/authorized testing only.

### Step 2: Deploy the Application

Use the app-deploy workflow (triggers full pipeline):

```bash
# Navigate to Actions → "App Build and Deploy" → Run workflow
# Image tag input: "latest" or a custom tag
```

Or manually:

```bash
cd terraform
terraform apply -var="image_tag=latest"

cd ..
docker build -t <acr-name>.azurecr.io/wiz-exercise:latest .
docker push <acr-name>.azurecr.io/wiz-exercise:latest
kubectl apply -f k8s/
```

### Step 3: Seed the Database

```bash
cd terraform
MONGO_IP=$(terraform output -raw mongo_vm_public_ip)
cd ..
python3 seed_db.py --host $MONGO_IP
```

Creates admin user in MongoDB.

---

## Usage Guide

### Accessing the Application

After deployment, get the AKS ingress endpoint:

```bash
cd terraform
terraform output -raw aks_ingress_endpoint
```

Navigate to `https://<ingress-endpoint>` in your browser.

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

## GitHub Actions Workflows

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `deploy.yml` | Manual (`workflow_dispatch`) | Infrastructure deployment only |
| `app-deploy.yml` | Manual (`workflow_dispatch`) | Build, push, and deploy app |
| `backup-cron.yml` | Scheduled (daily 2AM UTC) + Manual | MongoDB backup to Azure Blob (public access) |

---

## Security Warning

This project contains **intentionally vulnerable components** for educational/security testing purposes. It must not be deployed in production environments.

### Known Vulnerabilities

| Component | Vulnerability | Details |
|-----------|--------------|---------|
| MongoDB 3.2.22 | CVE-2018-9161 | Unauthenticated RCE via MONGODB-CR authentication |
| MongoDB | Default binding | Binds to 0.0.0.0 (all interfaces) |
| MongoDB | Public port | Port 27017 exposed via public IP |
| Admin credentials | Default creds | admin/admin123 |
| Flask app | Secret key | Default value (`dev-secret-key-change-in-prod`) when unset |
| Azure Blob | Public access | Container misconfigured with read access to all |
| Storage TLS | Weak TLS | `min_tls_version = TLS1_0` |
| ACR | Admin enabled | Admin user enabled for simplicity |

### Network Security Rules

| Port | Protocol | Source | Purpose |
|------|----------|--------|---------|
| 22 | TCP | `*` (world) | SSH to Mongo VM |
| 27017 | TCP | `10.0.2.0/24` (AKS) | MongoDB (AKS only) |

### Mitigation Recommendations (NOT applied)

- Use MongoDB 7.x instead of 3.2.22
- Enable authentication and authorization
- Restrict SSH access to VPN/bastion only
- Set a strong `SECRET_KEY` environment variable
- Disable ACR admin credentials
- Use TLS 1.2+ for all connections
- Restrict storage account to private endpoints