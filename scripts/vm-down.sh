#!/bin/bash
set -e

: "${1:?Usage: vm-down.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER>}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-automatic}

trap 'echo ""; echo "❌ [1/2] Sync failed! VM is still running. Fix the issue and re-run: make down"' ERR

echo "📤 [1/2] Syncing outputs and models to GCS..."
gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
  --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
  --command="gcloud storage rsync ~/stable-diffusion-webui/outputs/ ${BUCKET}/outputs/ --recursive && gcloud storage rsync ~/stable-diffusion-webui/models/Stable-diffusion/ ${BUCKET}/models/ --recursive" > /dev/null
echo "     ✅ Sync complete."

trap - ERR  # sync succeeded — clear trap so delete failure shows its own error
echo "🔥 [2/2] Destroying VM..."
gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet > /dev/null
echo "     ✅ VM destroyed."
echo ""
echo "✅ Done. No idle costs."