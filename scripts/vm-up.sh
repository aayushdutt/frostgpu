#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# Required variables are validated by lib.sh on load

wait_for_ssh() {
  log_step "Waiting for VM to accept SSH..."
  local max_attempts=20
  local attempt=1
  until ssh_cmd "$VM_USER" "$VM_NAME" "$ZONE" "echo ready" > /dev/null 2>&1; do
    if [[ $attempt -ge $max_attempts ]]; then
      log_error "VM unreachable after ${max_attempts} attempts. Aborting."
      exit 1
    fi
    echo "     Attempt ${attempt}/${max_attempts}... retrying in 2s"
    sleep 2
    ((attempt++))
  done
  log_info "VM is reachable."
}

# 1. Pre-flight
if vm_exists "$PROJECT_ID" "$ZONE" "$VM_NAME"; then
  log_warn "VM '$VM_NAME' already exists. Run 'make down' first."
  exit 1
fi

# 2. Find snapshot
log_step "Finding latest snapshot..."
SNAP_NAME=$(gcloud compute snapshots list \
  --project="$PROJECT_ID" \
  --filter="name~^${SNAPSHOT}-[0-9]" \
  --sort-by=~creationTimestamp --limit=1 --format="value(name)" 2>/dev/null)

if [[ -z "$SNAP_NAME" ]]; then
  log_error "No snapshot found with prefix '$SNAPSHOT'. Run 'make init' + 'make snapshot' first."
  exit 1
fi
log_info "Using snapshot '$SNAP_NAME'."

# 3. Create VM
if [[ "$VM_NAME" == *"-downloader" ]]; then
  gcloud compute instances create "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" \
    --machine-type="$DOWNLOADER_MACHINE_TYPE" \
    --provisioning-model=SPOT --maintenance-policy=TERMINATE \
    --source-snapshot="$SNAP_NAME" \
    --boot-disk-size="$DISK_SIZE" --boot-disk-type=pd-balanced \
    --scopes=https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append > /dev/null
else
  gcloud compute instances create "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --accelerator="$ACCELERATOR" \
    --provisioning-model=SPOT --maintenance-policy=TERMINATE \
    --source-snapshot="$SNAP_NAME" \
    --boot-disk-size="$DISK_SIZE" --boot-disk-type=pd-balanced \
    --scopes=https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/trace.append > /dev/null
fi
log_info "VM created."

wait_for_ssh

# 4. Data Persistence
if [[ "$VM_NAME" == *"-downloader" ]]; then
  mount_dirs "$BUCKET" "$VM_USER" "$VM_NAME" "$ZONE" "${SYNC_PAIRS[@]}"
else
  log_step "Pulling data from GCS..."
  sync_dirs "up" "$BUCKET" "$VM_USER" "$VM_NAME" "$ZONE" "${SYNC_PAIRS[@]}"
fi

log_info "System online. Use 'make tunnel' or 'make ssh' to connect."
