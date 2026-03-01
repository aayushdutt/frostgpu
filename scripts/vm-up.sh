#!/bin/bash
set -e

: "${1:?Usage: vm-up.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT_PREFIX> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5; VM_USER=${6:-$(whoami)}
shift 6
# Remaining args are "local:remote" sync pairs (space-separated, passed from Makefile)
SYNC_PAIRS=("$@")

ssh_cmd() {
  gcloud compute ssh "${VM_USER}@${VM}" --zone="$ZONE" \
    --ssh-flag="-o StrictHostKeyChecking=no" --ssh-flag="-o UserKnownHostsFile=/dev/null" \
    --command="$1"
}

wait_for_ssh() {
  echo "⏳ [2/3] Waiting for VM to accept SSH..."
  local max_attempts=20
  local attempt=1
  until ssh_cmd "echo ready" > /dev/null 2>&1; do
    if [[ $attempt -ge $max_attempts ]]; then
      echo "     ❌ VM unreachable after ${max_attempts} attempts. Aborting."
      exit 1
    fi
    echo "     Attempt ${attempt}/${max_attempts}... retrying in 10s"
    sleep 10
    ((attempt++))
  done
  echo "     ✅ VM is reachable."
}

# Bail out early if VM already exists
if gcloud compute instances describe "$VM" --project="$PROJECT" --zone="$ZONE" > /dev/null 2>&1; then
  echo "⚠️  VM '$VM' already exists. Run 'make down' first."
  exit 1
fi

# Find the latest timestamped snapshot
echo "📦 [1/3] Finding latest snapshot..."
SNAP_NAME=$(gcloud compute snapshots list \
  --project="$PROJECT" \
  --filter="name~^${SNAP}-[0-9]" \
  --sort-by=~creationTimestamp \
  --limit=1 \
  --format="value(name)" 2>/dev/null)

if [[ -z "$SNAP_NAME" ]]; then
  echo "     ❌ No snapshot found with prefix '$SNAP'. Run 'make init' + 'make snapshot' first."
  exit 1
fi
echo "     ✅ Using snapshot '$SNAP_NAME'."

gcloud compute instances create "$VM" --project="$PROJECT" --zone="$ZONE" \
  --machine-type=n1-standard-4 --accelerator=count=1,type=nvidia-tesla-t4 \
  --provisioning-model=SPOT --maintenance-policy=TERMINATE \
  --source-snapshot="$SNAP_NAME" \
  --boot-disk-size=50GB --boot-disk-type=pd-balanced \
  --scopes=https://www.googleapis.com/auth/cloud-platform > /dev/null
echo "     ✅ VM created."

wait_for_ssh

if [[ ${#SYNC_PAIRS[@]} -eq 0 ]]; then
  echo "ℹ️  [3/3] No SYNC_DIRS configured — skipping GCS sync."
else
  echo "📥 [3/3] Syncing from GCS..."
  for pair in "${SYNC_PAIRS[@]}"; do
    LOCAL="${pair%%:*}"
    REMOTE="${pair#*:}"
    echo "     ↓  ${BUCKET}/${REMOTE}/  →  ${LOCAL}"
    ssh_cmd "mkdir -p '${LOCAL}' && \
      (gcloud storage ls '${BUCKET}/${REMOTE}/' > /dev/null 2>&1 \
        && gcloud storage rsync '${BUCKET}/${REMOTE}/' '${LOCAL}/' --recursive \
        || echo 'No data at ${BUCKET}/${REMOTE}/ yet, skipping.')" > /dev/null
  done
  echo "     ✅ Sync complete."
fi

echo ""
echo "✅ System online. SSH in with 'make ssh' or open a tunnel with 'make ui'."