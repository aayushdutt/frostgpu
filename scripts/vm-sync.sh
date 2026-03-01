#!/bin/bash
set -e

: "${1:?Usage: vm-sync.sh <PROJECT> <BUCKET> <ZONE> <VM> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; VM_USER=${5:-$(whoami)}
shift 5
SYNC_PAIRS=("$@")

ssh_cmd() {
  gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
    --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
    --command="$1"
}

if [[ ${#SYNC_PAIRS[@]} -eq 0 ]]; then
  echo "ℹ️  No SYNC_DIRS configured — skipping GCS sync."
  exit 0
fi

echo "📤 Syncing to GCS..."
for pair in "${SYNC_PAIRS[@]}"; do
  LOCAL="${pair%%:*}"
  REMOTE="${pair#*:}"
  echo "     ↑  ${LOCAL}  →  ${BUCKET}/${REMOTE}/"
  ssh_cmd "gcloud storage rsync '${LOCAL}/' '${BUCKET}/${REMOTE}/' --recursive" > /dev/null
done
echo "     ✅ Sync complete."
