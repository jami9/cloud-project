#!/usr/bin/env bash
# ============================================================
# setup.sh — Run BEFORE terraform init
# Creates the k8s_terraform project/user in MicroStack,
# uploads Ubuntu image if missing, and installs Terraform.
# ============================================================
set -euo pipefail

ADMIN_PASSWORD="MSS5053ojTwjSGRBEgYSdH2vswXsNuIG"
TF_USER_PASSWORD="Password123"
PROJECT_NAME="k8s_terraform"
TF_USER="user_terraform"
IMAGE_NAME="ubuntu-22.04"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
TF_VERSION="1.7.5"

export OS_AUTH_URL="https://10.0.2.15:5000/v3"
export OS_PROJECT_NAME="admin"
export OS_USERNAME="admin"
export OS_PASSWORD="${ADMIN_PASSWORD}"
export OS_USER_DOMAIN_NAME="Default"
export OS_PROJECT_DOMAIN_NAME="Default"
export OS_IDENTITY_API_VERSION="3"
export OS_REGION_NAME="microstack"
export OS_CACERT="/var/snap/microstack/common/etc/ssl/certs/cacert.pem"

log() { echo -e "\033[1;32m[setup]\033[0m $*"; }
warn() { echo -e "\033[1;33m[warn]\033[0m $*"; }

# ---- 1. Create project ----
log "Creating project: ${PROJECT_NAME}"
microstack.openstack project create "${PROJECT_NAME}" 2>/dev/null \
  && log "  Project created." \
  || warn "  Project may already exist — continuing."

# ---- 2. Create user ----
log "Creating user: ${TF_USER}"
microstack.openstack user create "${TF_USER}" \
  --password "${TF_USER_PASSWORD}" 2>/dev/null \
  && log "  User created." \
  || warn "  User may already exist — continuing."

# ---- 3. Assign member role ----
log "Assigning member role to ${TF_USER} on ${PROJECT_NAME}"
microstack.openstack role add \
  --project "${PROJECT_NAME}" \
  --user "${TF_USER}" \
  member 2>/dev/null \
  && log "  Role assigned." \
  || warn "  Role may already be assigned — continuing."

# Also give admin role so the user can manage quotas/networks
log "Assigning admin role to ${TF_USER} on ${PROJECT_NAME}"
microstack.openstack role add \
  --project "${PROJECT_NAME}" \
  --user "${TF_USER}" \
  admin 2>/dev/null || true

# ---- 4. Update quotas ----
log "Updating quotas for project ${PROJECT_NAME}"
microstack.openstack quota set \
  --instances 10 \
  --cores 20 \
  --ram 20480 \
  --floating-ips 5 \
  --secgroups 10 \
  --secgroup-rules 100 \
  "${PROJECT_NAME}"

# ---- 5. Check / upload Ubuntu image ----
log "Checking for image: ${IMAGE_NAME}"
IMAGE_ID=$(microstack.openstack image list --name "${IMAGE_NAME}" -f value -c ID 2>/dev/null | head -1)

if [ -z "${IMAGE_ID}" ]; then
  log "Image not found — downloading from Ubuntu cloud images..."
  TMP_IMG=$(mktemp /tmp/ubuntu-22.04-XXXXXX.img)
  wget -q --show-progress "${IMAGE_URL}" -O "${TMP_IMG}"
  microstack.openstack image create "${IMAGE_NAME}" \
    --file "${TMP_IMG}" \
    --disk-format qcow2 \
    --container-format bare \
    --public \
    --min-disk 8 \
    --min-ram 2048
  rm -f "${TMP_IMG}"
  log "  Image uploaded: ${IMAGE_NAME}"
else
  log "  Image already exists: ${IMAGE_ID}"
fi

# ---- 6. Check flavor m1.small ----
log "Checking for flavor m1.small"
microstack.openstack flavor show m1.small &>/dev/null \
  && log "  Flavor m1.small exists." \
  || {
    warn "  Flavor m1.small not found — creating..."
    microstack.openstack flavor create m1.small \
      --vcpus 1 \
      --ram 2048 \
      --disk 20 \
      --public
    log "  Flavor m1.small created."
  }

# ---- 7. Install Terraform ----
if command -v terraform &>/dev/null; then
  log "Terraform already installed: $(terraform version | head -1)"
else
  log "Installing Terraform ${TF_VERSION}..."
  cd /tmp
  wget -q "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip"
  unzip -q "terraform_${TF_VERSION}_linux_amd64.zip"
  sudo mv terraform /usr/local/bin/
  rm -f "terraform_${TF_VERSION}_linux_amd64.zip"
  log "  Terraform installed: $(terraform version | head -1)"
fi

log "=========================================="
log "Setup complete. Next steps:"
log "  cd ~/cloud-project/k8s-terraform"
log "  terraform init"
log "  terraform plan"
log "  terraform apply"
log "=========================================="
