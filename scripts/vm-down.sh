#!/bin/bash
set -e

: "${1:?Usage: vm-down.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER>}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-automatic}

trap 'echo "⚠️  Sync failed! VM is still running. Fix the issue and re-run: make down"' ERR

echo "📤 Syncing outputs and models to GCS..."
gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
  --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
  --command="gcloud storage rsync ~/stable-diffusion-webui/outputs/ ${BUCKET}/outputs/ --recursive && gcloud storage rsync ~/stable-diffusion-webui/models/Stable-diffusion/ ${BUCKET}/models/ --recursive"

echo "🔥 Destroying VM (Zero Idle Cost Mode)..."
gcloud compute instances delete "$VM" --project="$PROJECT" --zone="$ZONE" --delete-disks=boot --quiet

echo "✅ VM destroyed. No idle costs."