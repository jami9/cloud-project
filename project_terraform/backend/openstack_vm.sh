#!/bin/bash

set -e

echo "======================================"
echo "  OpenStack Ubuntu Import Script"
echo "======================================"

# =========================
# CONFIGURATION
# =========================
SOURCE_IMAGE="/tmp/migration_staging/Ubuntu.qcow2"
DEST_DIR="/var/snap/microstack/common/images"
IMAGE_NAME="Ubuntu-VMware"
DEST_IMAGE="$DEST_DIR/Ubuntu.qcow2"

# =========================
# CHECK SOURCE IMAGE
# =========================
echo "✔ Vérification image source..."

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ ERREUR: Image source introuvable: $SOURCE_IMAGE"
    exit 1
fi

echo "✔ Image source trouvée: $SOURCE_IMAGE"

# =========================
# COPY IMAGE TO MICROSTACK
# =========================
echo "--------------------------------------"
echo "Copy image to MicroStack directory"
echo "--------------------------------------"

sudo cp "$SOURCE_IMAGE" "$DEST_IMAGE"
sudo chmod 644 "$DEST_IMAGE"

echo "✔ Image copiée vers: $DEST_IMAGE"

# =========================
# VERIFY DEST IMAGE
# =========================
echo "--------------------------------------"
echo "Verification destination image"
echo "--------------------------------------"

if [ ! -f "$DEST_IMAGE" ]; then
    echo "❌ ERREUR: Image destination introuvable: $DEST_IMAGE"
    exit 1
fi

ls -lh "$DEST_IMAGE"

# =========================
# UPLOAD TO GLANCE
# =========================
echo "--------------------------------------"
echo "Creating OpenStack Image (Glance)"
echo "--------------------------------------"

microstack.openstack image create "$IMAGE_NAME" \
  --file "$DEST_IMAGE" \
  --disk-format qcow2 \
  --container-format bare \
  --public \
  --property hw_disk_bus=virtio \
  --property hw_vif_model=virtio

# =========================
# SHOW RESULT
# =========================
echo "--------------------------------------"
echo "Image upload finished"
echo "--------------------------------------"

microstack.openstack image list

echo "--------------------------------------"
echo "Creating OpenStack Instance"
echo "--------------------------------------"

microstack.openstack server create \
  --image "Ubuntu-VMware" \
  --flavor m1.small \
  --network k8s-network \
  --key-name mykey \
  ubuntu-migre
echo "--------------------------------------"
echo "Server Created"
echo "--------------------------------------"

microstack.openstack server list
