#!/bin/bash
set -e

echo "======================================"
echo "  OpenStack K8s Import Script (multi-rôle)"
echo "======================================"

# =========================
# CONFIGURATION
# =========================
STAGING_DIR="/tmp/migration_staging"
DEST_DIR="/var/snap/microstack/common/images"

# Fichiers source confirmés : k8s-master.qcow2, k8s-worker1.qcow2, k8s-worker2.qcow2
declare -A ROLE_TO_IMAGE=(
  [master]="migrated-k8s-master"
  [worker1]="migrated-k8s-worker1"
  [worker2]="migrated-k8s-worker2"
)

# =========================
# IMPORT PAR RÔLE
# =========================
for role in master worker1 worker2; do
  IMAGE_NAME="${ROLE_TO_IMAGE[$role]}"
  SOURCE_IMAGE="$STAGING_DIR/k8s-${role}.qcow2"
  DEST_IMAGE="$DEST_DIR/k8s-${role}.qcow2"

  echo "--------------------------------------"
  echo "Rôle: $role  ->  Image Glance: $IMAGE_NAME"
  echo "--------------------------------------"

  # Vérification image source
  if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ ERREUR: Image source introuvable: $SOURCE_IMAGE"
    exit 1
  fi
  echo "✔ Image source trouvée: $SOURCE_IMAGE"

  # Copie vers le répertoire MicroStack (contournement du confinement snap)
  sudo cp "$SOURCE_IMAGE" "$DEST_IMAGE"
  sudo chmod 644 "$DEST_IMAGE"
  echo "✔ Image copiée vers: $DEST_IMAGE"

  # Vérification destination
  if [ ! -f "$DEST_IMAGE" ]; then
    echo "❌ ERREUR: Image destination introuvable: $DEST_IMAGE"
    exit 1
  fi
  ls -lh "$DEST_IMAGE"

  # Suppression de l'ancienne image Glance si elle existe encore
  if microstack.openstack image show "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "ℹ Suppression de l'ancienne image Glance: $IMAGE_NAME"
    microstack.openstack image delete "$IMAGE_NAME"
  fi

  # Upload vers Glance
  microstack.openstack image create "$IMAGE_NAME" \
    --file "$DEST_IMAGE" \
    --disk-format qcow2 \
    --container-format bare \
    --public \
    --property hw_disk_bus=virtio \
    --property hw_vif_model=virtio

  echo "✔ Image Glance créée: $IMAGE_NAME"
done

# =========================
# RÉSULTAT
# =========================
echo "--------------------------------------"
echo "Import terminé pour master / worker1 / worker2"
echo "--------------------------------------"
microstack.openstack image list

echo ""
echo "ℹ Les instances ne sont PAS créées par ce script."
echo "  Lance ensuite : terraform plan -out=deploy.tfplan && terraform apply deploy.tfplan"
echo "  dans ~/cloud-project/project_terraform/backend/k8s-terraform/"
