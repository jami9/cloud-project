#!/usr/bin/env bash
# ============================================================
# join-workers.sh — Run AFTER terraform apply
# Retrieves the join command from master and executes it
# on each worker node.
# ============================================================
set -euo pipefail

KEY="$HOME/cloud-project/mykey"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -i ${KEY}"

log() { echo -e "\033[1;36m[join]\033[0m $*"; }

# ---- Read IPs from terraform output ----
MASTER_IP=$(terraform output -raw master_floating_ip 2>/dev/null)
WORKER_IPS=$(terraform output -json worker_floating_ips 2>/dev/null | python3 -c "import sys,json; [print(ip) for ip in json.load(sys.stdin)]")

if [ -z "${MASTER_IP}" ]; then
  echo "ERROR: Run this script from the k8s-terraform directory after 'terraform apply'."
  exit 1
fi

log "Master: ${MASTER_IP}"

# ---- Wait for master cloud-init to finish ----
log "Waiting for master to complete initialisation..."
for i in $(seq 1 30); do
  ssh ${SSH_OPTS} ubuntu@${MASTER_IP} "test -f /home/ubuntu/join-command.sh" 2>/dev/null \
    && break || { echo -n "."; sleep 20; }
done
echo

# ---- Fetch join command ----
log "Fetching join command from master..."
JOIN_CMD=$(ssh ${SSH_OPTS} ubuntu@${MASTER_IP} "cat /home/ubuntu/join-command.sh")
log "Join command: ${JOIN_CMD}"

# ---- Execute on each worker ----
idx=1
for WORKER_IP in ${WORKER_IPS}; do
  log "Joining worker ${idx} (${WORKER_IP})..."
  
  # Wait for worker cloud-init to finish
  for i in $(seq 1 20); do
    ssh ${SSH_OPTS} ubuntu@${WORKER_IP} "command -v kubeadm" 2>/dev/null \
      && break || { echo -n "."; sleep 20; }
  done
  echo

  # Execute join (needs sudo)
  ssh ${SSH_OPTS} ubuntu@${WORKER_IP} "sudo ${JOIN_CMD}" \
    && log "  Worker ${idx} joined successfully." \
    || echo "  WARNING: Join may have failed — check manually."
  
  idx=$((idx + 1))
done

# ---- Verify cluster ----
log "Cluster node status:"
ssh ${SSH_OPTS} ubuntu@${MASTER_IP} "kubectl get nodes -o wide"

log "=========================================="
log "Cluster ready! Connect with:"
log "  ssh -i ${KEY} ubuntu@${MASTER_IP}"
log "  kubectl get nodes"
log "=========================================="
