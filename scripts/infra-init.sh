#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${1:?Usage: infra-init.sh <PROJECT_ID> <BUCKET> <ZONE> <VM_NAME>}"
PROJECT_ID=$1; BUCKET=$2; ZONE=$3; VM_NAME=$4

CLOUD_INIT="$SCRIPT_DIR/cloud-init.yaml"

if grep -q "YOUR_PUBLIC_SSH_KEY_HERE" "$CLOUD_INIT"; then
  echo "❌ Please replace YOUR_PUBLIC_SSH_KEY_HERE in scripts/cloud-init.yaml with your actual public SSH key first!"
  exit 1
fi

echo "🛠 Creating GCS Bucket..."
gcloud storage buckets create "$BUCKET" --location=europe-west2 --project="$PROJECT_ID" || echo "Bucket exists."

echo "🔥 Launching Base VM (First Time Setup)..."
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type=n1-standard-4 --accelerator=count=1,type=nvidia-tesla-t4 \
  --provisioning-model=SPOT --maintenance-policy=TERMINATE \
  --image-family=ubuntu-2404-lts-amd64-server --image-project=ubuntu-os-cloud \
  --boot-disk-size=50GB --boot-disk-type=pd-balanced \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata-from-file=user-data="$CLOUD_INIT"