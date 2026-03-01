#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

: "${1:?Usage: vm-up.sh <PROJECT> <BUCKET> <ZONE> <VM> <SNAPSHOT_PREFIX> <VM_USER> [SYNC_DIRS...]}"
PROJECT=$1; BUCKET=$2; ZONE=$3; VM=$4; SNAP=$5; VM_USER=${6:-$(whoami)}
shift 6
SYNC_PAIRS=("$@")

wait_for_ssh() {
  log_step "Waiting for VM to accept SSH..."
  local max_attempts=20
  local attempt=1
  until ssh_cmd "$VM_USER" "$VM" "$ZONE" "echo ready" > /dev/null 2>&1; do
    if [[ $attempt -ge $max_attempts ]]; then
      log_error "VM unreachable after ${max_attempts} attempts. Aborting."
      exit 1
    fi
    echo "     Attempt ${attempt}/${max_attempts}... retrying in 10s"
    sleep 10
    ((attempt++))
  done
  log_info "VM is reachable."
}

# 1. Pre-flight
if vm_exists "$PROJECT" "$ZONE" "$VM"; then
  log_warn "VM '$VM' already exists. Run 'make down' first."
  exit 1
fi

# 2. Find snapshot
log_step "Finding latest snapshot..."
SNAP_NAME=$(gcloud compute snapshots list \
  --project="$PROJECT" \
  --filter="name~^${SNAP}-[0-9]" \
  --sort-by=~creationTimestamp --limit=1 --format="value(name)" 2>/dev/null)

if [[ -z "$SNAP_NAME" ]]; then
  log_error "No snapshot found with prefix '$SNAP'. Run 'make init' + 'make snapshot' first."
  exit 1
fi
log_info "Using snapshot '$SNAP_NAME'."

# 3. Create VM
gcloud compute instances create "$VM" --project="$PROJECT" --zone="$ZONE" \
  --machine-type="${MACHINE_TYPE:-n1-standard-4}" \
  --accelerator="${ACCELERATOR:-count=1,type=nvidia-tesla-t4}" \
  --provisioning-model=SPOT --maintenance-policy=TERMINATE \
  --source-snapshot="$SNAP_NAME" \
  --boot-disk-size=50GB --boot-disk-type=pd-balanced \
  --scopes=https://www.googleapis.com/auth/cloud-platform > /dev/null
log_info "VM created."

wait_for_ssh

# 4. Sync Data
log_step "Pulling data from GCS..."
sync_dirs "up" "$BUCKET" "$VM_USER" "$VM" "$ZONE" "${SYNC_PAIRS[@]}"
log_info "System online. Use 'make tunnel' or 'make ssh' to connect."