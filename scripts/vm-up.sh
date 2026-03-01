#!/bin/bash
set -e

: "${1:?Usage: vm-up.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT> <VM_USER>}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5; VM_USER=${6:-automatic}

wait_for_ssh() {
  echo "⏳ Waiting for VM to accept SSH connections..."
  local max_attempts=20
  local attempt=1
  until gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
    --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
    --command="echo ready" > /dev/null 2>&1; do
    if [[ $attempt -ge $max_attempts ]]; then
      echo "❌ VM did not become reachable after ${max_attempts} attempts. Aborting."
      exit 1
    fi
    echo "   Attempt ${attempt}/${max_attempts}... retrying in 10s"
    sleep 10
    ((attempt++))
  done
  echo "✅ VM is reachable."
}

# Check if snapshot exists
if gcloud compute snapshots describe "$SNAP" --project="$PROJECT" > /dev/null 2>&1; then
  echo "📦 Found Snapshot. Restoring Save State..."
  gcloud compute instances create "$VM" --project="$PROJECT" --zone="$ZONE" \
    --source-snapshot="$SNAP" --machine-type=n1-standard-4 \
    --accelerator=count=1,type=nvidia-tesla-t4 --provisioning-model=SPOT \
    --boot-disk-size=50GB --boot-disk-type=pd-balanced \
    --scopes=https://www.googleapis.com/auth/cloud-platform --maintenance-policy=TERMINATE
else
  echo "❌ No snapshot found. Run 'make init' first to create the base VM and golden image."
  exit 1
fi

wait_for_ssh

echo "📥 Syncing models from $BUCKET..."
gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
  --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
  --command="mkdir -p ~/stable-diffusion-webui/models/Stable-diffusion && gcloud storage rsync ${BUCKET}/models/ ~/stable-diffusion-webui/models/Stable-diffusion/ --recursive"

echo "✅ System online."