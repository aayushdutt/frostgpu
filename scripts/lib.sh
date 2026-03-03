#!/bin/bash

# Shared constants
SSH_FLAGS=("-o" "StrictHostKeyChecking=no" "-o" "UserKnownHostsFile=/dev/null")

# Load configuration if environment file exists
# This handles the case where scripts are run directly without the Makefile.
# If variables are already set (e.g., via Makefile export), we don't re-source and overwrite.
if [ -z "$PROJECT_ID" ]; then
  # ENV_FILE is provided by the Makefile as the filename (e.g. .env.t4)
  # If empty, we default to the standard .env
  TARGET_ENV="${ENV:-$SCRIPT_DIR/../.env}"
  
  if [[ -f "$TARGET_ENV" ]]; then
    export $(grep -v '^#' "$TARGET_ENV" | xargs)
  elif [[ -f "$SCRIPT_DIR/../$TARGET_ENV" ]]; then
    # In case ENV is a relative filename from the root
    export $(grep -v '^#' "$SCRIPT_DIR/../$TARGET_ENV" | xargs)
  fi
fi

# Logging helpers
log_info()    { echo -e "     ✅ \033[0;32m$1\033[0m"; }
log_warn()    { echo -e "     ⚠️  \033[0;33m$1\033[0m"; }
log_error()   { echo -e "     ❌ \033[0;31m$1\033[0m"; }
log_step()    { echo -e "\n\033[1;34m$1\033[0m"; }

# Centralized SSH executor
ssh_cmd() {
  local user=$1
  local vm=$2
  local zone=$3
  local cmd=$4
  gcloud compute ssh "${user}@${vm}" --zone="${zone}" \
    "${SSH_FLAGS[@]/#/--ssh-flag=}" \
    --command="${cmd}"
}

# Resource checking
vm_exists() {
  local project=$1; local zone=$2; local vm=$3
  gcloud compute instances describe "$vm" --project="$project" --zone="$zone" > /dev/null 2>&1
}

bucket_exists() {
  local project=$1; local bucket=$2
  gcloud storage buckets describe "$bucket" --project="$project" > /dev/null 2>&1
}

# Data Syncing Logic
# Usage: sync_dirs <DIRECTION: up|down> <BUCKET> <VM_USER> <VM_NAME> <ZONE> [SYNC_PAIRS...]
sync_dirs() {
  local direction=$1; local bucket=$2; local user=$3; local vm=$4; local zone=$5
  shift 5
  local pairs=("$@")

  if [[ ${#pairs[@]} -eq 0 ]]; then
    log_warn "No SYNC_DIRS configured — skipping GCS sync."
    return
  fi

  for pair in "${pairs[@]}"; do
    local local_path="${pair%%:*}"
    local remote_path="${pair#*:}"
    
    if [[ "$direction" == "up" ]]; then
      # Pull: GCS -> VM
      echo "     ↓  ${bucket}/${remote_path}/  →  ${local_path}"
      ssh_cmd "$user" "$vm" "$zone" "mkdir -p '${local_path}' && \
        (gcloud storage ls '${bucket}/${remote_path}/' > /dev/null 2>&1 \
          && gcloud storage rsync '${bucket}/${remote_path}/' '${local_path}/' --recursive \
          || echo 'No data at ${bucket}/${remote_path}/ yet, skipping.')" > /dev/null
    else
      # Push: VM -> GCS
      echo "     ↑  ${local_path}  →  ${bucket}/${remote_path}/"
      ssh_cmd "$user" "$vm" "$zone" "gcloud storage rsync '${local_path}/' '${bucket}/${remote_path}/' --recursive" > /dev/null
    fi
  done
}

# Mount Logic (Downloader Mode)
# Usage: mount_dirs <BUCKET> <VM_USER> <VM_NAME> <ZONE> [SYNC_PAIRS...]
mount_dirs() {
  local bucket=$1; local user=$2; local vm=$3; local zone=$4
  shift 4
  local pairs=("$@")
  local bucket_name=${bucket#gs://}

  log_step "Mounting GCS folders (FUSE)..."
  for pair in "${pairs[@]}"; do
    local local_path="${pair%%:*}"
    local remote_path="${pair#*:}"
    
    echo "     🔗  ${bucket}/${remote_path}/  ↔  ${local_path}"
    # We use --implicit-dirs so that gcsfuse sees directories even if there are no placeholder objects
    # We use --only-dir to mount a specific subfolder as the root of the mount point
    ssh_cmd "$user" "$vm" "$zone" "mkdir -p '${local_path}' && \
      gcsfuse --implicit-dirs --only-dir '${remote_path}' '${bucket_name}' '${local_path}'" > /dev/null
  done
}

unmount_dirs() {
  local user=$1; local vm=$2; local zone=$3
  shift 3
  local pairs=("$@")

  log_step "Unmounting GCS folders..."
  for pair in "${pairs[@]}"; do
    local local_path="${pair%%:*}"
    echo "     ⏏️  ${local_path}"
    ssh_cmd "$user" "$vm" "$zone" "fusermount -u '${local_path}' || true" > /dev/null
  done
}
