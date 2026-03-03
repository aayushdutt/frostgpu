#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: infra-init.sh <PROJECT_ID> <BUCKET> <ZONE> <VM_NAME> <VM_USER>}"
PROJECT_ID=$1; BUCKET=$2; ZONE=$3; VM_NAME=$4; VM_USER=$5

REGION="${ZONE%-*}"
CLOUD_INIT_SRC="$SCRIPT_DIR/cloud-init.yaml"
CLOUD_INIT_TEMP="/tmp/cloud-init-${VM_NAME}.yaml"

# Replace {{VM_USER}} in cloud-init.yaml
sed "s/{{VM_USER}}/$VM_USER/g" "$CLOUD_INIT_SRC" > "$CLOUD_INIT_TEMP"

log_step "[1/2] Creating GCS Bucket..."
gcloud storage buckets create "$BUCKET" --location="$REGION" --project="$PROJECT_ID" > /dev/null 2>&1 \
  && log_info "Bucket ready." || log_warn "Bucket already exists."

log_step "[2/2] Launching Base VM (${MACHINE_TYPE:-g2-standard-4} + ${ACCELERATOR:-L4})..."
gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type="${MACHINE_TYPE:-g2-standard-4}" \
  --accelerator="${ACCELERATOR:-count=1,type=nvidia-l4}" \
  --provisioning-model=SPOT --maintenance-policy=TERMINATE \
  --image-family=ubuntu-2404-lts-amd64 --image-project=ubuntu-os-cloud \
  --boot-disk-size="${DISK_SIZE:-50GB}" --boot-disk-type=pd-balanced \
  --scopes=https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append \
  --metadata-from-file=user-data="$CLOUD_INIT_TEMP" > /dev/null

rm "$CLOUD_INIT_TEMP"
log_info "VM '$VM_NAME' created."

echo ""
log_step "⏳ Nvidia drivers are installing in the background (~10 min)."
echo "   Run 'make ssh' then: tail -f /var/log/gpu-driver-install.log"